// Manifest types and serialization
// This will be expanded in later tasks

use serde::{Deserialize, Serialize};

/// Manifest schema version 1.0
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    pub schema_version: String,
    pub dataset: Dataset,
    pub source: Source,
    pub contents: Vec<Content>,
    #[serde(default)]
    pub transformations: Vec<Transformation>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Dataset {
    pub name: String,
    pub version: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Source {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub download_date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub server_mtime: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub archive_hash: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Content {
    pub path: String,
    pub hash: String,
    pub size: u64,
    #[serde(default)]
    pub executable: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Transformation {
    #[serde(rename = "type")]
    pub transform_type: String,
    pub from: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<serde_json::Value>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_manifest_serialization() {
        let manifest = Manifest {
            schema_version: "1.0".to_string(),
            dataset: Dataset {
                name: "test".to_string(),
                version: "1.0.0".to_string(),
                description: None,
            },
            source: Source {
                url: None,
                download_date: None,
                server_mtime: None,
                archive_hash: None,
            },
            contents: vec![],
            transformations: vec![],
        };

        let json = serde_json::to_string(&manifest).unwrap();
        assert!(json.contains("test"));
    }
}
