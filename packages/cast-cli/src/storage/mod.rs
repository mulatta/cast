// Storage backend trait and implementations
pub mod config;
pub mod local;

use anyhow::Result;
use async_trait::async_trait;
use std::path::PathBuf;

use crate::hash::Blake3Hash;
use crate::manifest::Manifest;

/// Storage backend trait for content-addressed storage operations
///
/// All methods are async to support various backend types (local, remote, etc.)
#[async_trait]
pub trait StorageBackend: Send + Sync {
    /// Store data and return its BLAKE3 hash
    ///
    /// The data is read from the provided reader, hashed, and stored
    /// in the content-addressed storage. Returns the hash for retrieval.
    async fn put(&self, data: &[u8]) -> Result<Blake3Hash>;

    /// Retrieve file path by hash
    ///
    /// Returns the path to the file in CAS. The file may be a symlink
    /// to the actual storage location.
    async fn get(&self, hash: &Blake3Hash) -> Result<PathBuf>;

    /// Check if hash exists in storage
    async fn exists(&self, hash: &Blake3Hash) -> bool;

    /// Delete data by hash
    ///
    /// Note: This should respect reference counting in production.
    /// For now, it directly removes the file.
    async fn delete(&self, hash: &Blake3Hash) -> Result<()>;

    /// Register a dataset manifest
    ///
    /// This will be used with the metadata database in Task 7
    async fn register_dataset(&self, manifest: &Manifest) -> Result<()>;
}

pub use config::StorageConfig;
