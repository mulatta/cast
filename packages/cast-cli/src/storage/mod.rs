// Storage backend trait and implementations
// This will be fully implemented in task 6

use anyhow::Result;
use std::path::PathBuf;

/// Storage backend trait for CAS operations
pub trait StorageBackend: Send + Sync {
    /// Store data and return its BLAKE3 hash
    fn put(&self, data: &[u8]) -> Result<String>;

    /// Retrieve path to data by hash
    fn get(&self, hash: &str) -> Result<PathBuf>;

    /// Check if hash exists in storage
    fn exists(&self, hash: &str) -> bool;

    /// Delete data by hash (respects reference counting)
    fn delete(&self, hash: &str) -> Result<()>;
}

// Local storage implementation will be added in task 6
