// SQLite metadata database
use anyhow::{Context, Result};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePool, SqlitePoolOptions};
use sqlx::{Row, SqliteConnection};
use std::path::Path;
use std::str::FromStr;

/// Metadata database for tracking CAS objects, datasets, and transformations
pub struct MetadataDb {
    pool: SqlitePool,
}

impl MetadataDb {
    /// Create or open database at the specified path
    ///
    /// If the database doesn't exist, it will be created.
    /// The schema will be initialized automatically.
    pub async fn new(db_path: impl AsRef<Path>) -> Result<Self> {
        let db_path = db_path.as_ref();

        // Create parent directory if it doesn't exist
        if let Some(parent) = db_path.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .with_context(|| format!("Failed to create database directory: {}", parent.display()))?;
        }

        // Configure SQLite connection
        let connection_string = format!("sqlite:{}", db_path.display());
        let options = SqliteConnectOptions::from_str(&connection_string)?
            .create_if_missing(true)
            .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal)
            .synchronous(sqlx::sqlite::SqliteSynchronous::Normal);

        // Create connection pool
        let pool = SqlitePoolOptions::new()
            .max_connections(5)
            .connect_with(options)
            .await
            .with_context(|| format!("Failed to connect to database: {}", db_path.display()))?;

        let db = Self { pool };

        // Initialize schema
        db.initialize_schema().await?;

        tracing::info!("Opened metadata database: {}", db_path.display());

        Ok(db)
    }

    /// Initialize the database schema
    async fn initialize_schema(&self) -> Result<()> {
        // Create schema version table
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY,
                applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            "#,
        )
        .execute(&self.pool)
        .await?;

        // Check current schema version
        let current_version = self.get_schema_version().await?;

        if current_version < 1 {
            self.apply_migration_v1().await?;
            self.set_schema_version(1).await?;
        }

        Ok(())
    }

    /// Get current schema version
    async fn get_schema_version(&self) -> Result<i32> {
        let row = sqlx::query("SELECT COALESCE(MAX(version), 0) as version FROM schema_version")
            .fetch_one(&self.pool)
            .await?;

        Ok(row.get("version"))
    }

    /// Set schema version
    async fn set_schema_version(&self, version: i32) -> Result<()> {
        sqlx::query("INSERT INTO schema_version (version) VALUES (?)")
            .bind(version)
            .execute(&self.pool)
            .await?;

        tracing::info!("Applied schema version {}", version);
        Ok(())
    }

    /// Apply migration version 1 - initial schema
    async fn apply_migration_v1(&self) -> Result<()> {
        // Objects table - tracks all content-addressed objects
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS objects (
                hash TEXT PRIMARY KEY,
                size INTEGER NOT NULL,
                refs INTEGER DEFAULT 1,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                metadata TEXT
            )
            "#,
        )
        .execute(&self.pool)
        .await?;

        // Datasets table - tracks registered datasets
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS datasets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                version TEXT NOT NULL,
                manifest_hash TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(name, version),
                FOREIGN KEY (manifest_hash) REFERENCES objects(hash)
            )
            "#,
        )
        .execute(&self.pool)
        .await?;

        // Transformations table - tracks transformation history
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS transformations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                input_hash TEXT NOT NULL,
                output_hash TEXT NOT NULL,
                transform_type TEXT NOT NULL,
                params TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (input_hash) REFERENCES objects(hash),
                FOREIGN KEY (output_hash) REFERENCES objects(hash)
            )
            "#,
        )
        .execute(&self.pool)
        .await?;

        // Create indexes for common queries
        sqlx::query("CREATE INDEX IF NOT EXISTS idx_objects_refs ON objects(refs)")
            .execute(&self.pool)
            .await?;

        sqlx::query("CREATE INDEX IF NOT EXISTS idx_datasets_name ON datasets(name)")
            .execute(&self.pool)
            .await?;

        sqlx::query("CREATE INDEX IF NOT EXISTS idx_transformations_input ON transformations(input_hash)")
            .execute(&self.pool)
            .await?;

        sqlx::query("CREATE INDEX IF NOT EXISTS idx_transformations_output ON transformations(output_hash)")
            .execute(&self.pool)
            .await?;

        tracing::info!("Created database schema v1");
        Ok(())
    }

    // ========== Object Operations ==========

    /// Register an object in the database
    ///
    /// If the object already exists, increment its reference count.
    pub async fn register_object(
        &self,
        hash: &str,
        size: i64,
        metadata: Option<String>,
    ) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO objects (hash, size, metadata)
            VALUES (?, ?, ?)
            ON CONFLICT(hash) DO UPDATE SET refs = refs + 1
            "#,
        )
        .bind(hash)
        .bind(size)
        .bind(metadata)
        .execute(&self.pool)
        .await
        .with_context(|| format!("Failed to register object: {}", hash))?;

        tracing::debug!("Registered object: {}", hash);
        Ok(())
    }

    /// Get object metadata
    pub async fn get_object(&self, hash: &str) -> Result<Option<ObjectRecord>> {
        let record = sqlx::query_as::<_, ObjectRecord>(
            "SELECT hash, size, refs, created_at, metadata FROM objects WHERE hash = ?",
        )
        .bind(hash)
        .fetch_optional(&self.pool)
        .await?;

        Ok(record)
    }

    /// Update object reference count
    pub async fn update_refs(&self, hash: &str, delta: i32) -> Result<()> {
        sqlx::query("UPDATE objects SET refs = refs + ? WHERE hash = ?")
            .bind(delta)
            .bind(hash)
            .execute(&self.pool)
            .await
            .with_context(|| format!("Failed to update refs for: {}", hash))?;

        Ok(())
    }

    /// Delete object from database
    ///
    /// This should only be called when refs reach 0
    pub async fn delete_object(&self, hash: &str) -> Result<()> {
        sqlx::query("DELETE FROM objects WHERE hash = ?")
            .bind(hash)
            .execute(&self.pool)
            .await
            .with_context(|| format!("Failed to delete object: {}", hash))?;

        tracing::debug!("Deleted object from database: {}", hash);
        Ok(())
    }

    /// Get all objects with zero references (candidates for GC)
    pub async fn get_unreferenced_objects(&self) -> Result<Vec<String>> {
        let hashes = sqlx::query_scalar("SELECT hash FROM objects WHERE refs <= 0")
            .fetch_all(&self.pool)
            .await?;

        Ok(hashes)
    }

    // ========== Dataset Operations ==========

    /// Register a dataset
    pub async fn register_dataset(
        &self,
        name: &str,
        version: &str,
        manifest_hash: &str,
    ) -> Result<i64> {
        let result = sqlx::query(
            r#"
            INSERT INTO datasets (name, version, manifest_hash)
            VALUES (?, ?, ?)
            ON CONFLICT(name, version) DO UPDATE SET manifest_hash = excluded.manifest_hash
            RETURNING id
            "#,
        )
        .bind(name)
        .bind(version)
        .bind(manifest_hash)
        .fetch_one(&self.pool)
        .await
        .with_context(|| format!("Failed to register dataset: {}/{}", name, version))?;

        let id: i64 = result.get("id");

        tracing::info!("Registered dataset: {}/{} (id: {})", name, version, id);
        Ok(id)
    }

    /// Find datasets by name
    pub async fn find_datasets_by_name(&self, name: &str) -> Result<Vec<DatasetRecord>> {
        let records = sqlx::query_as::<_, DatasetRecord>(
            "SELECT id, name, version, manifest_hash, created_at FROM datasets WHERE name = ? ORDER BY created_at DESC",
        )
        .bind(name)
        .fetch_all(&self.pool)
        .await?;

        Ok(records)
    }

    /// Get dataset by name and version
    pub async fn get_dataset(&self, name: &str, version: &str) -> Result<Option<DatasetRecord>> {
        let record = sqlx::query_as::<_, DatasetRecord>(
            "SELECT id, name, version, manifest_hash, created_at FROM datasets WHERE name = ? AND version = ?",
        )
        .bind(name)
        .bind(version)
        .fetch_optional(&self.pool)
        .await?;

        Ok(record)
    }

    /// Get all dataset versions
    pub async fn get_dataset_versions(&self, name: &str) -> Result<Vec<String>> {
        let versions = sqlx::query_scalar(
            "SELECT version FROM datasets WHERE name = ? ORDER BY created_at DESC",
        )
        .bind(name)
        .fetch_all(&self.pool)
        .await?;

        Ok(versions)
    }

    // ========== Transformation Operations ==========

    /// Register a transformation
    pub async fn register_transformation(
        &self,
        input_hash: &str,
        output_hash: &str,
        transform_type: &str,
        params: Option<String>,
    ) -> Result<i64> {
        let result = sqlx::query(
            r#"
            INSERT INTO transformations (input_hash, output_hash, transform_type, params)
            VALUES (?, ?, ?, ?)
            RETURNING id
            "#,
        )
        .bind(input_hash)
        .bind(output_hash)
        .bind(transform_type)
        .bind(params)
        .fetch_one(&self.pool)
        .await
        .with_context(|| {
            format!(
                "Failed to register transformation: {} -> {}",
                input_hash, output_hash
            )
        })?;

        let id: i64 = result.get("id");

        tracing::info!("Registered transformation: {} (id: {})", transform_type, id);
        Ok(id)
    }

    /// Get transformation chain for an output hash
    ///
    /// Returns transformations ordered from original source to final output
    pub async fn get_transformation_chain(&self, hash: &str) -> Result<Vec<TransformationRecord>> {
        let records = sqlx::query_as::<_, TransformationRecord>(
            r#"
            WITH RECURSIVE chain(id, input_hash, output_hash, transform_type, params, created_at, depth) AS (
                SELECT id, input_hash, output_hash, transform_type, params, created_at, 0
                FROM transformations
                WHERE output_hash = ?
                UNION ALL
                SELECT t.id, t.input_hash, t.output_hash, t.transform_type, t.params, t.created_at, c.depth + 1
                FROM transformations t
                INNER JOIN chain c ON t.output_hash = c.input_hash
            )
            SELECT id, input_hash, output_hash, transform_type, params, created_at
            FROM chain
            ORDER BY depth DESC
            "#,
        )
        .bind(hash)
        .fetch_all(&self.pool)
        .await?;

        Ok(records)
    }

    /// Find cached transformation result
    pub async fn find_cached_transformation(
        &self,
        input_hash: &str,
        transform_type: &str,
        params: Option<&str>,
    ) -> Result<Option<String>> {
        let output_hash = sqlx::query_scalar::<_, String>(
            r#"
            SELECT output_hash FROM transformations
            WHERE input_hash = ? AND transform_type = ? AND params IS ?
            ORDER BY created_at DESC
            LIMIT 1
            "#,
        )
        .bind(input_hash)
        .bind(transform_type)
        .bind(params)
        .fetch_optional(&self.pool)
        .await?;

        Ok(output_hash)
    }

    // ========== Transaction Support ==========

    /// Begin a transaction
    pub async fn begin_transaction(&self) -> Result<sqlx::Transaction<'_, sqlx::Sqlite>> {
        let tx = self.pool.begin().await?;
        Ok(tx)
    }

    /// Execute multiple operations in a transaction
    pub async fn with_transaction<F, T>(&self, f: F) -> Result<T>
    where
        F: for<'c> FnOnce(&'c mut SqliteConnection) -> futures::future::BoxFuture<'c, Result<T>> + Send,
        T: Send,
    {
        let mut tx = self.pool.begin().await?;
        let result = f(&mut tx).await?;
        tx.commit().await?;
        Ok(result)
    }

    /// Get database statistics
    pub async fn get_stats(&self) -> Result<DatabaseStats> {
        let objects_count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM objects")
                .fetch_one(&self.pool)
                .await?;

        let datasets_count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM datasets")
                .fetch_one(&self.pool)
                .await?;

        let transformations_count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM transformations")
                .fetch_one(&self.pool)
                .await?;

        let total_size: i64 =
            sqlx::query_scalar("SELECT COALESCE(SUM(size), 0) FROM objects")
                .fetch_one(&self.pool)
                .await?;

        Ok(DatabaseStats {
            objects_count,
            datasets_count,
            transformations_count,
            total_size,
        })
    }
}

// ========== Record Types ==========

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct ObjectRecord {
    pub hash: String,
    pub size: i64,
    pub refs: i32,
    pub created_at: String,
    pub metadata: Option<String>,
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct DatasetRecord {
    pub id: i64,
    pub name: String,
    pub version: String,
    pub manifest_hash: String,
    pub created_at: String,
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct TransformationRecord {
    pub id: i64,
    pub input_hash: String,
    pub output_hash: String,
    pub transform_type: String,
    pub params: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone)]
pub struct DatabaseStats {
    pub objects_count: i64,
    pub datasets_count: i64,
    pub transformations_count: i64,
    pub total_size: i64,
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    async fn create_test_db() -> (MetadataDb, TempDir) {
        let temp_dir = TempDir::new().unwrap();
        let db_path = temp_dir.path().join("test.db");
        let db = MetadataDb::new(&db_path).await.unwrap();
        (db, temp_dir)
    }

    #[tokio::test]
    async fn test_db_creation() {
        let (db, _temp) = create_test_db().await;
        let stats = db.get_stats().await.unwrap();
        assert_eq!(stats.objects_count, 0);
    }

    #[tokio::test]
    async fn test_register_object() {
        let (db, _temp) = create_test_db().await;

        db.register_object("hash1", 1000, Some("test metadata".to_string()))
            .await
            .unwrap();

        let obj = db.get_object("hash1").await.unwrap().unwrap();
        assert_eq!(obj.hash, "hash1");
        assert_eq!(obj.size, 1000);
        assert_eq!(obj.refs, 1);
    }

    #[tokio::test]
    async fn test_object_ref_counting() {
        let (db, _temp) = create_test_db().await;

        db.register_object("hash1", 1000, None).await.unwrap();
        db.register_object("hash1", 1000, None).await.unwrap(); // Duplicate

        let obj = db.get_object("hash1").await.unwrap().unwrap();
        assert_eq!(obj.refs, 2);

        db.update_refs("hash1", -1).await.unwrap();
        let obj = db.get_object("hash1").await.unwrap().unwrap();
        assert_eq!(obj.refs, 1);
    }

    #[tokio::test]
    async fn test_delete_object() {
        let (db, _temp) = create_test_db().await;

        db.register_object("hash1", 1000, None).await.unwrap();
        assert!(db.get_object("hash1").await.unwrap().is_some());

        db.delete_object("hash1").await.unwrap();
        assert!(db.get_object("hash1").await.unwrap().is_none());
    }

    #[tokio::test]
    async fn test_unreferenced_objects() {
        let (db, _temp) = create_test_db().await;

        db.register_object("hash1", 1000, None).await.unwrap();
        db.register_object("hash2", 2000, None).await.unwrap();

        db.update_refs("hash1", -1).await.unwrap(); // refs = 0

        let unreferenced = db.get_unreferenced_objects().await.unwrap();
        assert_eq!(unreferenced.len(), 1);
        assert_eq!(unreferenced[0], "hash1");
    }

    #[tokio::test]
    async fn test_register_dataset() {
        let (db, _temp) = create_test_db().await;

        // Register object first (foreign key constraint)
        db.register_object("manifest_hash", 100, None)
            .await
            .unwrap();

        let id = db
            .register_dataset("test-dataset", "1.0.0", "manifest_hash")
            .await
            .unwrap();
        assert!(id > 0);

        let dataset = db
            .get_dataset("test-dataset", "1.0.0")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(dataset.name, "test-dataset");
        assert_eq!(dataset.version, "1.0.0");
    }

    #[tokio::test]
    async fn test_find_datasets_by_name() {
        let (db, _temp) = create_test_db().await;

        // Register objects first
        db.register_object("hash1", 100, None).await.unwrap();
        db.register_object("hash2", 200, None).await.unwrap();

        db.register_dataset("test", "1.0.0", "hash1")
            .await
            .unwrap();
        db.register_dataset("test", "2.0.0", "hash2")
            .await
            .unwrap();

        let datasets = db.find_datasets_by_name("test").await.unwrap();
        assert_eq!(datasets.len(), 2);
    }

    #[tokio::test]
    async fn test_get_dataset_versions() {
        let (db, _temp) = create_test_db().await;

        // Register objects first
        db.register_object("hash1", 100, None).await.unwrap();
        db.register_object("hash2", 200, None).await.unwrap();

        db.register_dataset("test", "1.0.0", "hash1")
            .await
            .unwrap();
        db.register_dataset("test", "2.0.0", "hash2")
            .await
            .unwrap();

        let versions = db.get_dataset_versions("test").await.unwrap();
        assert_eq!(versions.len(), 2);
        assert!(versions.contains(&"1.0.0".to_string()));
        assert!(versions.contains(&"2.0.0".to_string()));
    }

    #[tokio::test]
    async fn test_register_transformation() {
        let (db, _temp) = create_test_db().await;

        // Register objects first
        db.register_object("input_hash", 100, None).await.unwrap();
        db.register_object("output_hash", 200, None).await.unwrap();

        let id = db
            .register_transformation("input_hash", "output_hash", "extract", Some("{}".to_string()))
            .await
            .unwrap();
        assert!(id > 0);
    }

    #[tokio::test]
    async fn test_find_cached_transformation() {
        let (db, _temp) = create_test_db().await;

        // Register objects first
        db.register_object("input1", 100, None).await.unwrap();
        db.register_object("output1", 200, None).await.unwrap();

        db.register_transformation("input1", "output1", "extract", None)
            .await
            .unwrap();

        let cached = db
            .find_cached_transformation("input1", "extract", None)
            .await
            .unwrap();
        assert_eq!(cached, Some("output1".to_string()));

        let not_cached = db
            .find_cached_transformation("input2", "extract", None)
            .await
            .unwrap();
        assert_eq!(not_cached, None);
    }

    #[tokio::test]
    async fn test_get_transformation_chain() {
        let (db, _temp) = create_test_db().await;

        // Register objects first
        db.register_object("hash0", 100, None).await.unwrap();
        db.register_object("hash1", 200, None).await.unwrap();
        db.register_object("hash2", 300, None).await.unwrap();

        db.register_transformation("hash0", "hash1", "extract", None)
            .await
            .unwrap();
        db.register_transformation("hash1", "hash2", "convert", None)
            .await
            .unwrap();

        let chain = db.get_transformation_chain("hash2").await.unwrap();
        assert_eq!(chain.len(), 2);
        assert_eq!(chain[0].transform_type, "extract");
        assert_eq!(chain[1].transform_type, "convert");
    }

    #[tokio::test]
    async fn test_database_stats() {
        let (db, _temp) = create_test_db().await;

        db.register_object("hash1", 1000, None).await.unwrap();
        db.register_object("hash2", 2000, None).await.unwrap();
        // hash1 is registered as an object, so we can reference it
        db.register_dataset("test", "1.0.0", "hash1")
            .await
            .unwrap();

        let stats = db.get_stats().await.unwrap();
        assert_eq!(stats.objects_count, 2);
        assert_eq!(stats.datasets_count, 1);
        assert_eq!(stats.total_size, 3000);
    }
}
