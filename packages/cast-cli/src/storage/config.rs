// Storage configuration management
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tokio::fs;

/// Storage configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StorageConfig {
    /// Root directory for CAS storage
    pub root: PathBuf,

    /// Storage type (currently only "local" is supported)
    #[serde(default = "default_storage_type")]
    pub storage_type: String,
}

fn default_storage_type() -> String {
    "local".to_string()
}

impl StorageConfig {
    /// Load configuration with the following priority:
    /// 1. CAST_STORE environment variable
    /// 2. config.toml file
    /// 3. Default: ~/.cache/cast
    pub async fn load() -> Result<Self> {
        // Priority 1: Environment variable
        if let Ok(env_path) = std::env::var("CAST_STORE") {
            return Ok(Self {
                root: PathBuf::from(env_path),
                storage_type: "local".to_string(),
            });
        }

        // Priority 2: Config file
        if let Some(config_path) = Self::config_file_path() {
            if config_path.exists() {
                let content = fs::read_to_string(&config_path)
                    .await
                    .with_context(|| format!("Failed to read config file: {}", config_path.display()))?;

                let config: StorageConfig = toml::from_str(&content)
                    .with_context(|| format!("Failed to parse config file: {}", config_path.display()))?;

                return Ok(config);
            }
        }

        // Priority 3: Default
        Ok(Self::default())
    }

    /// Get the config file path (~/.config/cast/config.toml)
    fn config_file_path() -> Option<PathBuf> {
        dirs::config_dir().map(|dir| dir.join("cast").join("config.toml"))
    }

    /// Save configuration to config file
    pub async fn save(&self) -> Result<()> {
        let config_path = Self::config_file_path()
            .context("Failed to determine config directory")?;

        // Create parent directory
        if let Some(parent) = config_path.parent() {
            fs::create_dir_all(parent)
                .await
                .with_context(|| format!("Failed to create config directory: {}", parent.display()))?;
        }

        let content = toml::to_string_pretty(self)
            .context("Failed to serialize config")?;

        fs::write(&config_path, content)
            .await
            .with_context(|| format!("Failed to write config file: {}", config_path.display()))?;

        Ok(())
    }

    /// Get the store directory path
    pub fn store_path(&self) -> PathBuf {
        self.root.join("store")
    }

    /// Get the metadata database path
    pub fn db_path(&self) -> PathBuf {
        self.root.join("meta.db")
    }
}

impl Default for StorageConfig {
    fn default() -> Self {
        let root = dirs::cache_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("cast");

        Self {
            root,
            storage_type: "local".to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = StorageConfig::default();
        assert_eq!(config.storage_type, "local");
        assert!(config.root.ends_with("cast"));
    }

    #[test]
    fn test_store_path() {
        let config = StorageConfig {
            root: PathBuf::from("/tmp/test-cast"),
            storage_type: "local".to_string(),
        };

        assert_eq!(config.store_path(), PathBuf::from("/tmp/test-cast/store"));
    }

    #[test]
    fn test_db_path() {
        let config = StorageConfig {
            root: PathBuf::from("/tmp/test-cast"),
            storage_type: "local".to_string(),
        };

        assert_eq!(config.db_path(), PathBuf::from("/tmp/test-cast/meta.db"));
    }

    #[tokio::test]
    async fn test_load_from_env() {
        std::env::set_var("CAST_STORE", "/tmp/env-test");

        let config = StorageConfig::load().await.unwrap();
        assert_eq!(config.root, PathBuf::from("/tmp/env-test"));

        std::env::remove_var("CAST_STORE");
    }
}
