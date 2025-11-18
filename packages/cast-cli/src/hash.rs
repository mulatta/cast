// BLAKE3 hashing implementation
use anyhow::{Context, Result};
use blake3::{Hash, Hasher};
use serde::{Deserialize, Serialize};
use std::fmt;
use std::fs::File;
use std::io::{BufReader, Read};
use std::path::Path;
use std::str::FromStr;

/// BLAKE3 hash wrapper with convenient methods
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Blake3Hash(Hash);

impl Blake3Hash {
    /// Compute BLAKE3 hash from a file using streaming I/O
    ///
    /// This uses a buffered reader to handle large files efficiently
    /// without loading the entire file into memory.
    pub fn from_file<P: AsRef<Path>>(path: P) -> Result<Self> {
        let path = path.as_ref();
        let file =
            File::open(path).with_context(|| format!("Failed to open file: {}", path.display()))?;

        let reader = BufReader::with_capacity(1024 * 1024, file); // 1MB buffer
        Self::from_reader(reader)
            .with_context(|| format!("Failed to hash file: {}", path.display()))
    }

    /// Compute BLAKE3 hash from any reader
    ///
    /// Reads data in chunks to support streaming hashing
    pub fn from_reader<R: Read>(mut reader: R) -> Result<Self> {
        let mut hasher = Hasher::new();
        let mut buffer = [0u8; 16384]; // 16KB chunks

        loop {
            let bytes_read = reader
                .read(&mut buffer)
                .context("Failed to read data for hashing")?;
            if bytes_read == 0 {
                break;
            }
            hasher.update(&buffer[..bytes_read]);
        }

        Ok(Blake3Hash(hasher.finalize()))
    }

    /// Compute BLAKE3 hash from bytes in memory
    ///
    /// This is optimized for small data that fits in memory
    pub fn from_bytes(data: &[u8]) -> Self {
        Blake3Hash(blake3::hash(data))
    }

    /// Get the underlying blake3::Hash
    pub fn as_hash(&self) -> &Hash {
        &self.0
    }

    /// Get hex string representation without prefix
    pub fn to_hex(&self) -> String {
        self.0.to_hex().to_string()
    }

    /// Get hex string with blake3: prefix
    pub fn to_string_prefixed(&self) -> String {
        format!("blake3:{}", self.to_hex())
    }

    /// Verify this hash matches the given string (with or without prefix)
    pub fn verify(&self, other: &str) -> bool {
        // Try with prefix first
        if let Ok(parsed) = Self::from_str(other) {
            return *self == parsed;
        }

        // Try as raw hex
        if other.len() == 64 {
            if let Ok(parsed) = Self::from_str(&format!("blake3:{}", other)) {
                return *self == parsed;
            }
        }

        false
    }

    /// Get the hash as bytes
    pub fn as_bytes(&self) -> &[u8; 32] {
        self.0.as_bytes()
    }
}

impl fmt::Display for Blake3Hash {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.to_string_prefixed())
    }
}

impl FromStr for Blake3Hash {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self> {
        let hex = s.strip_prefix("blake3:").unwrap_or(s);

        if hex.len() != 64 {
            anyhow::bail!("Invalid BLAKE3 hash length: expected 64 hex chars, got {}", hex.len());
        }

        let bytes = hex::decode(hex)
            .with_context(|| format!("Failed to decode hex hash: {}", hex))?;

        if bytes.len() != 32 {
            anyhow::bail!("Invalid BLAKE3 hash: expected 32 bytes, got {}", bytes.len());
        }

        let mut hash_bytes = [0u8; 32];
        hash_bytes.copy_from_slice(&bytes);

        Ok(Blake3Hash(Hash::from(hash_bytes)))
    }
}

impl Serialize for Blake3Hash {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.to_string_prefixed())
    }
}

impl<'de> Deserialize<'de> for Blake3Hash {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        Blake3Hash::from_str(&s).map_err(serde::de::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn test_hash_empty_bytes() {
        let hash = Blake3Hash::from_bytes(b"");
        assert_eq!(
            hash.to_hex(),
            "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"
        );
    }

    #[test]
    fn test_hash_hello_world() {
        let hash = Blake3Hash::from_bytes(b"hello world");
        // Known BLAKE3 hash for "hello world"
        assert_eq!(
            hash.to_hex(),
            "d74981efa70a0c880b8d8c1985d075dbcbf679b99a5f9914e5aaf96b831a9e24"
        );
    }

    #[test]
    fn test_hash_with_prefix() {
        let hash = Blake3Hash::from_bytes(b"test");
        let prefixed = hash.to_string_prefixed();
        assert!(prefixed.starts_with("blake3:"));
        assert_eq!(prefixed.len(), 71); // "blake3:" (7) + 64 hex chars
    }

    #[test]
    fn test_hash_display() {
        let hash = Blake3Hash::from_bytes(b"test");
        let display = format!("{}", hash);
        assert!(display.starts_with("blake3:"));
    }

    #[test]
    fn test_hash_from_str() {
        let original = Blake3Hash::from_bytes(b"test data");
        let hex_str = original.to_string_prefixed();

        let parsed = Blake3Hash::from_str(&hex_str).unwrap();
        assert_eq!(original, parsed);
    }

    #[test]
    fn test_hash_from_str_without_prefix() {
        let original = Blake3Hash::from_bytes(b"test data");
        let hex_only = original.to_hex();

        let parsed = Blake3Hash::from_str(&hex_only).unwrap();
        assert_eq!(original, parsed);
    }

    #[test]
    fn test_hash_from_str_invalid() {
        assert!(Blake3Hash::from_str("invalid").is_err());
        assert!(Blake3Hash::from_str("blake3:tooshort").is_err());
        assert!(Blake3Hash::from_str("blake3:zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz").is_err());
    }

    #[test]
    fn test_hash_verify() {
        let hash = Blake3Hash::from_bytes(b"verify test");
        let prefixed = hash.to_string_prefixed();
        let hex_only = hash.to_hex();

        assert!(hash.verify(&prefixed));
        assert!(hash.verify(&hex_only));
        assert!(!hash.verify("invalid"));
        assert!(!hash.verify("blake3:0000000000000000000000000000000000000000000000000000000000000000"));
    }

    #[test]
    fn test_hash_from_reader() {
        let data = b"streaming test data";
        let cursor = Cursor::new(data);

        let hash = Blake3Hash::from_reader(cursor).unwrap();
        let expected = Blake3Hash::from_bytes(data);

        assert_eq!(hash, expected);
    }

    #[test]
    fn test_hash_from_reader_large() {
        // Test with data larger than buffer size
        let data = vec![0xAB; 100_000]; // 100KB of 0xAB
        let cursor = Cursor::new(&data);

        let hash = Blake3Hash::from_reader(cursor).unwrap();
        let expected = Blake3Hash::from_bytes(&data);

        assert_eq!(hash, expected);
    }

    #[test]
    fn test_hash_serialization() {
        let hash = Blake3Hash::from_bytes(b"serialize me");
        let json = serde_json::to_string(&hash).unwrap();

        assert!(json.contains("blake3:"));

        let deserialized: Blake3Hash = serde_json::from_str(&json).unwrap();
        assert_eq!(hash, deserialized);
    }

    #[test]
    fn test_hash_consistency() {
        // Same input should always produce same hash
        let data = b"consistency test";

        let hash1 = Blake3Hash::from_bytes(data);
        let hash2 = Blake3Hash::from_bytes(data);
        let hash3 = Blake3Hash::from_reader(Cursor::new(data)).unwrap();

        assert_eq!(hash1, hash2);
        assert_eq!(hash2, hash3);
    }

    #[test]
    fn test_hash_as_bytes() {
        let hash = Blake3Hash::from_bytes(b"test");
        let bytes = hash.as_bytes();

        assert_eq!(bytes.len(), 32);

        // Reconstruct from bytes
        let reconstructed = Blake3Hash(Hash::from(*bytes));
        assert_eq!(hash, reconstructed);
    }
}
