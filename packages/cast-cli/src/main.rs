use clap::{Parser, Subcommand};
use anyhow::Result;

mod db;
mod hash;
mod manifest;
mod storage;

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
            tracing::info!("Transforming dataset: {}", input_manifest);
            tracing::info!("Output directory: {}", output_dir);
            tracing::info!("Transform type: {}", transform_type);
            println!("Stub: Would transform dataset");
            println!("This will be implemented in task 9 (Transform pipeline)");
            Ok(())
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

    #[test]
    fn test_cli_parsing() {
        // Test that CLI parsing works
        use clap::CommandFactory;
        Cli::command().debug_assert();
    }
}
