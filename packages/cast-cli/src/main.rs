use clap::{Parser, Subcommand};
use anyhow::{Context, Result};
use std::path::Path;

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

mod db;
mod hash;
mod manifest;
mod storage;

use hash::Blake3Hash;
use manifest::{Content, Manifest, Transformation};

#[derive(Parser)]
#[command(name = "cast")]
#[command(about = "Content-Addressed Storage Tool", long_about = None)]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Store a file in CAS and return its hash
    Put {
        /// Path to the file to store
        file: String,
    },

    /// Retrieve file path by hash
    Get {
        /// BLAKE3 hash of the file
        hash: String,
    },

    /// Download and register a database
    Fetch {
        /// URL to download from
        url: String,

        /// Expected BLAKE3 hash (optional)
        #[arg(long)]
        hash: Option<String>,
    },

    /// Transform a dataset
    Transform {
        /// Path to input manifest
        #[arg(long)]
        input_manifest: String,

        /// Output directory
        #[arg(long)]
        output_dir: String,

        /// Transformation type
        #[arg(long)]
        transform_type: String,
    },

    /// Garbage collect unreferenced objects
    Gc {
        /// Dry run - don't actually delete anything
        #[arg(long)]
        dry_run: bool,
    },
}

/// Transform command implementation
async fn transform_command(
    input_manifest: &str,
    output_dir: &str,
    transform_type: &str,
) -> Result<()> {
    tracing::info!("Processing transformation: {}", transform_type);
    tracing::info!("Input manifest: {}", input_manifest);
    tracing::info!("Output directory: {}", output_dir);

    // Read and parse input manifest
    let input_content = tokio::fs::read_to_string(input_manifest)
        .await
        .with_context(|| format!("Failed to read input manifest: {}", input_manifest))?;

    let input_manifest_data: Manifest = serde_json::from_str(&input_content)
        .with_context(|| format!("Failed to parse input manifest: {}", input_manifest))?;

    // Scan output directory for files
    let output_path = Path::new(output_dir);
    if !output_path.exists() {
        anyhow::bail!("Output directory does not exist: {}", output_dir);
    }

    let mut contents = Vec::new();
    let mut entries = tokio::fs::read_dir(output_path).await?;

    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        if path.is_file() {
            // Hash the file
            let hash = Blake3Hash::from_file(&path)
                .with_context(|| format!("Failed to hash file: {}", path.display()))?;

            // Get file metadata
            let metadata = tokio::fs::metadata(&path).await?;
            let size = metadata.len();

            #[cfg(unix)]
            let executable = metadata.permissions().mode() & 0o111 != 0;
            #[cfg(not(unix))]
            let executable = false;

            // Get relative path
            let rel_path = path
                .strip_prefix(output_path)
                .unwrap()
                .to_string_lossy()
                .to_string();

            contents.push(Content {
                path: rel_path,
                hash: hash.to_hex(),
                size,
                executable,
            });

            tracing::debug!("Processed file: {} (hash: {})", path.display(), hash);
        }
    }

    if contents.is_empty() {
        anyhow::bail!("No files found in output directory: {}", output_dir);
    }

    tracing::info!("Processed {} output files", contents.len());

    // Get source hash for provenance
    let source_hash = input_manifest_data
        .source
        .archive_hash
        .clone()
        .unwrap_or_else(|| "blake3:unknown".to_string());

    // Create transformation record
    let new_transformation = Transformation {
        transform_type: transform_type.to_string(),
        from: source_hash.clone(),
        params: None,
    };

    // Build transformations array (preserve existing + add new)
    let mut transformations = input_manifest_data.transformations.clone();
    transformations.push(new_transformation);

    // Generate output manifest
    let output_manifest = Manifest {
        schema_version: "1.0".to_string(),
        dataset: input_manifest_data.dataset.clone(),
        source: input_manifest_data.source.clone(),
        contents,
        transformations,
    };

    // Output manifest as JSON to stdout
    let manifest_json = serde_json::to_string_pretty(&output_manifest)
        .context("Failed to serialize output manifest")?;

    println!("{}", manifest_json);

    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing subscriber for logging
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    let cli = Cli::parse();

    match cli.command {
        Commands::Put { file } => {
            tracing::info!("Storing file: {}", file);
            println!("Stub: Would store file {}", file);
            println!("This will be implemented in task 5 (BLAKE3 hashing)");
            Ok(())
        }
        Commands::Get { hash } => {
            tracing::info!("Retrieving file with hash: {}", hash);
            println!("Stub: Would retrieve file with hash {}", hash);
            println!("This will be implemented in task 6 (Local storage backend)");
            Ok(())
        }
        Commands::Fetch { url, hash } => {
            tracing::info!("Fetching from URL: {}", url);
            if let Some(h) = hash {
                tracing::info!("Expected hash: {}", h);
            }
            println!("Stub: Would fetch from {}", url);
            println!("This will be implemented in Phase 2");
            Ok(())
        }
        Commands::Transform {
            input_manifest,
            output_dir,
            transform_type,
        } => {
            transform_command(&input_manifest, &output_dir, &transform_type).await
        }
        Commands::Gc { dry_run } => {
            tracing::info!("Running garbage collection (dry_run: {})", dry_run);
            println!("Stub: Would run garbage collection");
            println!("This will be implemented in Phase 4");
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_cli_parsing() {
        // Test that CLI parsing works
        use clap::CommandFactory;
        Cli::command().debug_assert();
    }

    #[tokio::test]
    async fn test_transform_command() {
        // Create temp directory for output
        let temp_dir = TempDir::new().unwrap();
        let output_dir = temp_dir.path();

        // Create a test file in output directory
        let test_file = output_dir.join("test.txt");
        tokio::fs::write(&test_file, b"transformed data").await.unwrap();

        // Create input manifest
        let manifest_dir = TempDir::new().unwrap();
        let input_manifest_path = manifest_dir.path().join("input-manifest.json");

        let input_manifest = Manifest {
            schema_version: "1.0".to_string(),
            dataset: manifest::Dataset {
                name: "test-dataset".to_string(),
                version: "1.0.0".to_string(),
                description: Some("Test dataset".to_string()),
            },
            source: manifest::Source {
                url: Some("test://input".to_string()),
                download_date: Some("2024-01-01T00:00:00Z".to_string()),
                server_mtime: None,
                archive_hash: Some("blake3:input123".to_string()),
            },
            contents: vec![],
            transformations: vec![],
        };

        let manifest_json = serde_json::to_string_pretty(&input_manifest).unwrap();
        tokio::fs::write(&input_manifest_path, manifest_json).await.unwrap();

        // Run transform command
        let result = transform_command(
            input_manifest_path.to_str().unwrap(),
            output_dir.to_str().unwrap(),
            "test-transform",
        ).await;

        assert!(result.is_ok(), "Transform command failed: {:?}", result.err());
    }
}
