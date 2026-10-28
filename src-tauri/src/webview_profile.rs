use crate::path_scope;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};

// 不同项目或内核版本不能复用仍被旧进程占用的 WebView2 环境
pub fn directory(base: &Path, scope: Option<&str>, runtime_version: &str) -> PathBuf {
    let scope = scope.map(|scope| path_scope::path_key(Path::new(scope)));
    let mut hasher = DefaultHasher::new();
    (scope, runtime_version).hash(&mut hasher);
    base.join("webviews").join(format!("{:016x}", hasher.finish()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn isolates_projects_and_runtime_versions_but_keeps_repeat_launches_stable() {
        let base = Path::new(r"C:\cache");
        let current = directory(base, Some(r"E:\project\Client"), "156.0");
        assert_eq!(current, directory(base, Some("e:/project/client/"), "156.0"));
        assert_ne!(current, directory(base, Some(r"D:\project\Client"), "156.0"));
        assert_ne!(current, directory(base, Some(r"E:\project\Client"), "155.0"));
        assert_ne!(current, directory(base, None, "156.0"));
        assert!(current.starts_with(base.join("webviews")));
    }
}
