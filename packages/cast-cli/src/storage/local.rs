// Local filesystem storage backend
use super::{StorageBackend, StorageConfig};
use crate::hash::Blake3Hash;
use crate::manifest::Manifest;
use anyhow::{Context, Result};
use async_trait::async_trait;
use std::path::{Path, PathBuf};
use tokio::fs;
use tokio::io::AsyncWriteExt;

/// Local filesystem storage backend
///
/// Stores files in a hierarchical directory structure based on hash:
/// `store/{hash[:2]}/{hash[2:4]}/{full_hash}`
pub struct LocalStorage {
    config: StorageConfig,
}

impl LocalStorage {
    /// Create a new LocalStorage instance with the given configuration
    pub fn new(config: StorageConfig) -> Self {
        Self { config }
    }

    /// Create a new LocalStorage instance from a root path
    pub fn with_root<P: AsRef<Path>>(root: P) -> Self {
        let config = StorageConfig {
            root: root.as_ref().to_path_buf(),
            storage_type: "local".to_string(),
        };
        Self::new(config)
    }

    /// Load storage from configuration (env var, config file, or default)
    pub async fn load() -> Result<Self> {
        let config = StorageConfig::load().await?;
        Ok(Self::new(config))
    }

    /// Convert a BLAKE3 hash to its storage path
    ///
    /// Uses hierarchical directory structure: `store/{hash[:2]}/{hash[2:4]}/{full_hash}`
    /// This avoids having too many files in a single directory.
    fn hash_to_path(&self, hash: &Blake3Hash) -> PathBuf {
        let hex = hash.to_hex();

        self.config.store_path()
            .join(&hex[..2])
            .join(&hex[2..4])
            .join(&hex)
    }

    /// Get the root directory for storage
    pub fn root(&self) -> &Path {
        &self.config.root
    }

    /// Get the store directory (root/store/)
    pub fn store_path(&self) -> PathBuf {
        self.config.store_path()
    }

    /// Initialize storage directories
    ///
    /// Creates the necessary directory structure if it doesn't exist
    pub async fn initialize(&self) -> Result<()> {
        fs::create_dir_all(&self.config.root)
            .await
            .with_context(|| format!("Failed to create storage root: {}", self.config.root.display()))?;

        fs::create_dir_all(self.config.store_path())
            .await
            .with_context(|| format!("Failed to create store directory: {}", self.config.store_path().display()))?;

        Ok(())
    }
}

#[async_trait]
impl StorageBackend for LocalStorage {
    async fn put(&self, data: &[u8]) -> Result<Blake3Hash> {
        // Calculate hash
        let hash = Blake3Hash::from_bytes(data);

        // Get storage path
        let path = self.hash_to_path(&hash);

        // Check if file already exists (deduplication)
        if path.exists() {
            tracing::debug!("File already exists: {}", hash);
            return Ok(hash);
        }

        // Create parent directories
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .await
                .with_context(|| format!("Failed to create directory: {}", parent.display()))?;
        }

        // Write file
        let mut file = fs::File::create(&path)
            .await
            .with_context(|| format!("Failed to create file: {}", path.display()))?;

        file.write_all(data)
            .await
            .with_context(|| format!("Failed to write data to: {}", path.display()))?;

        file.sync_all()
            .await
            .with_context(|| format!("Failed to sync file: {}", path.display()))?;

        tracing::info!("Stored file: {} ({} bytes)", hash, data.len());

        Ok(hash)
    }

    async fn get(&self, hash: &Blake3Hash) -> Result<PathBuf> {
        let path = self.hash_to_path(hash);

        if !path.exists() {
            anyhow::bail!("File not found in CAS: {}", hash);
        }

        Ok(path)
    }

    async fn exists(&self, hash: &Blake3Hash) -> bool {
        self.hash_to_path(hash).exists()
    }

    async fn delete(&self, hash: &Blake3Hash) -> Result<()> {
        let path = self.hash_to_path(hash);

        if !path.exists() {
            anyhow::bail!("File not found for deletion: {}", hash);
        }

        fs::remove_file(&path)
            .await
            .with_context(|| format!("Failed to delete file: {}", path.display()))?;

        tracing::info!("Deleted file: {}", hash);

        // Optionally clean up empty parent directories
        self.cleanup_empty_dirs(&path).await?;

        Ok(())
    }

    async fn register_dataset(&self, _manifest: &Manifest) -> Result<()> {
        // This will be implemented in Task 7 with SQLite integration
        tracing::warn!("Dataset registration not yet implemented (Task 7)");
        Ok(())
    }
}

impl LocalStorage {
    /// Clean up empty parent directories after file deletion
    async fn cleanup_empty_dirs(&self, path: &Path) -> Result<()> {
        if let Some(parent) = path.parent() {
            // Only clean up within the store directory
            if parent.starts_with(self.config.store_path()) {
                // Try to remove the directory (will only succeed if empty)
                let _ = fs::remove_dir(parent).await;

                // Try to remove grandparent (hash[2:4] directory)
                if let Some(grandparent) = parent.parent() {
                    if grandparent.starts_with(self.config.store_path()) {
                        let _ = fs::remove_dir(grandparent).await;
                    }
                }
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    async fn create_test_storage() -> (LocalStorage, TempDir) {
        let temp_dir = TempDir::new().unwrap();
        let storage = LocalStorage::with_root(temp_dir.path());
        storage.initialize().await.unwrap();
        (storage, temp_dir)
    }

    #[tokio::test]
    async fn test_put_and_get() {
        let (storage, _temp) = create_test_storage().await;

        let data = b"test data for storage";
        let hash = storage.put(data).await.unwrap();

        let path = storage.get(&hash).await.unwrap();
        assert!(path.exists());

        let retrieved = fs::read(&path).await.unwrap();
        assert_eq!(retrieved, data);
    }

    #[tokio::test]
    async fn test_exists() {
        let (storage, _temp) = create_test_storage().await;

        let data = b"existence test";
        let hash = storage.put(data).await.unwrap();

        assert!(storage.exists(&hash).await);

        let fake_hash = Blake3Hash::from_bytes(b"nonexistent");
        assert!(!storage.exists(&fake_hash).await);
    }

    #[tokio::test]
    async fn test_delete() {
        let (storage, _temp) = create_test_storage().await;

        let data = b"delete me";
        let hash = storage.put(data).await.unwrap();

        assert!(storage.exists(&hash).await);

        storage.delete(&hash).await.unwrap();

        assert!(!storage.exists(&hash).await);
    }

    #[tokio::test]
    async fn test_deduplication() {
        let (storage, _temp) = create_test_storage().await;

        let data = b"duplicate data";

        let hash1 = storage.put(data).await.unwrap();
        let hash2 = storage.put(data).await.unwrap();

        assert_eq!(hash1, hash2);

        // File should only exist once
        let path = storage.hash_to_path(&hash1);
        assert!(path.exists());
    }

    #[tokio::test]
    async fn test_hash_to_path_structure() {
        let temp_dir = TempDir::new().unwrap();
        let storage = LocalStorage::with_root(temp_dir.path());

        let hash = Blake3Hash::from_bytes(b"test");
        let path = storage.hash_to_path(&hash);

        // Check hierarchical structure
        let hex = hash.to_hex();
        assert!(path.to_str().unwrap().contains(&hex[..2]));
        assert!(path.to_str().unwrap().contains(&hex[2..4]));
        assert!(path.ends_with(&hex));
    }

    #[tokio::test]
    async fn test_concurrent_puts() {
        let (storage, _temp) = create_test_storage().await;

        let data1 = b"concurrent 1";
        let data2 = b"concurrent 2";
        let data3 = b"concurrent 3";

        let (hash1, hash2, hash3) = tokio::join!(
            storage.put(data1),
            storage.put(data2),
            storage.put(data3)
        );

        assert!(hash1.is_ok());
        assert!(hash2.is_ok());
        assert!(hash3.is_ok());

        // All should be retrievable
        assert!(storage.exists(&hash1.unwrap()).await);
        assert!(storage.exists(&hash2.unwrap()).await);
        assert!(storage.exists(&hash3.unwrap()).await);
    }

    #[tokio::test]
    async fn test_large_file() {
        let (storage, _temp) = create_test_storage().await;

        // Create 1MB file
        let data = vec![0xAB; 1_000_000];
        let hash = storage.put(&data).await.unwrap();

        let path = storage.get(&hash).await.unwrap();
        let retrieved = fs::read(&path).await.unwrap();

        assert_eq!(retrieved.len(), data.len());
        assert_eq!(retrieved, data);
    }

    #[test]
    fn test_storage_config() {
        let config = StorageConfig {
            root: PathBuf::from("/tmp/test"),
            storage_type: "local".to_string(),
        };

        let storage = LocalStorage::new(config);
        assert_eq!(storage.root(), Path::new("/tmp/test"));
        assert_eq!(storage.store_path(), PathBuf::from("/tmp/test/store"));
    }
}
