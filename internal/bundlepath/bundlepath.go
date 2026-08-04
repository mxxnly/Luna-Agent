package bundlepath

import (
	"os"
	"path/filepath"
)

// AppBundleRoot returns LunaAgent.app root when this process runs from
// Contents/MacOS/<binary>, otherwise "".
func AppBundleRoot() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	exe, err = filepath.EvalSymlinks(exe)
	if err != nil {
		return ""
	}
	// .../LunaAgent.app/Contents/MacOS/<name>
	macos := filepath.Dir(exe)
	contents := filepath.Dir(macos)
	if filepath.Base(macos) != "MacOS" || filepath.Base(contents) != "Contents" {
		return ""
	}
	return filepath.Dir(contents)
}

// LunaWGDir is Contents/Resources/luna-wg inside the app bundle, if present.
func LunaWGDir() string {
	root := AppBundleRoot()
	if root == "" {
		return ""
	}
	dir := filepath.Join(root, "Contents", "Resources", "luna-wg")
	if st, err := os.Stat(dir); err == nil && st.IsDir() {
		return dir
	}
	return ""
}

// ToolCandidates returns ordered paths to search for a WireGuard tool.
func ToolCandidates(name string) []string {
	var out []string
	if dir := LunaWGDir(); dir != "" {
		out = append(out, filepath.Join(dir, name))
	}
	// Absolute install fallback (current /Applications).
	out = append(out,
		"/Applications/LunaAgent.app/Contents/Resources/luna-wg/"+name,
		"/usr/local/libexec/luna-wg/"+name, // legacy scatter (migration)
		"/opt/homebrew/bin/"+name,
		"/usr/local/bin/"+name,
	)
	return out
}

// ToolPATH prepends bundled luna-wg (and common bins) for child processes.
func ToolPATH(existing string) string {
	prefix := "/Applications/LunaAgent.app/Contents/Resources/luna-wg:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
	if dir := LunaWGDir(); dir != "" {
		prefix = dir + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
	}
	if existing == "" {
		return prefix
	}
	return prefix + ":" + existing
}
