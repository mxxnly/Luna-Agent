package wg

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"time"

	"github.com/mxxnly/Luna-Agent/internal/bundlepath"
)

const (
	helperDaemonLabel = "com.lunaagent.wghelper"
	helperDaemonPlist = "/Library/LaunchDaemons/com.lunaagent.wghelper.plist"
)

// EnsureRootHelper installs the WireGuard LaunchDaemon once (Mac password dialog)
// so Connect/Disconnect use the Unix socket instead of osascript every time.
func EnsureRootHelper() error {
	if helperAvailable() {
		return nil
	}
	if os.Getenv("LUNA_WG_NO_ELEVATE") == "1" {
		return fmt.Errorf("wg helper not running")
	}
	if runtime.GOOS != "darwin" {
		return fmt.Errorf("wg helper install supported on macOS only")
	}
	bin := helperBinaryPath()
	if bin == "" {
		return fmt.Errorf("luna-wghelper missing inside LunaAgent.app — reinstall the pkg")
	}

	stage, err := stageHelperPlist(bin)
	if err != nil {
		return err
	}
	defer os.Remove(stage)

	shell := fmt.Sprintf(
		`cp %q %q && chmod 644 %q && (launchctl bootout system/%s 2>/dev/null || launchctl unload -w %q 2>/dev/null || true) && launchctl bootstrap system %q && launchctl enable system/%s && launchctl kickstart -k system/%s`,
		stage, helperDaemonPlist, helperDaemonPlist,
		helperDaemonLabel, helperDaemonPlist,
		helperDaemonPlist, helperDaemonLabel, helperDaemonLabel,
	)
	if err := runElevated(shell); err != nil {
		return fmt.Errorf("install wg helper: %w", err)
	}

	deadline := time.Now().Add(12 * time.Second)
	for time.Now().Before(deadline) {
		if helperAvailable() {
			return nil
		}
		time.Sleep(250 * time.Millisecond)
	}
	return fmt.Errorf("wg helper did not start — check Console for luna-wghelper")
}

func helperBinaryPath() string {
	if p := os.Getenv("LUNA_WGHELPER_BIN"); p != "" {
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			return p
		}
	}
	if root := bundlepath.AppBundleRoot(); root != "" {
		p := filepath.Join(root, "Contents", "MacOS", "luna-wghelper")
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			return p
		}
	}
	p := "/Applications/LunaAgent.app/Contents/MacOS/luna-wghelper"
	if st, err := os.Stat(p); err == nil && !st.IsDir() {
		return p
	}
	return ""
}

func stageHelperPlist(bin string) (string, error) {
	body := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>%s</string>
	<key>ProgramArguments</key>
	<array>
		<string>%s</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ThrottleInterval</key>
	<integer>5</integer>
</dict>
</plist>
`, helperDaemonLabel, bin)

	dir := filepath.Join(os.TempDir(), "lunaagent")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	stage := filepath.Join(dir, "com.lunaagent.wghelper.plist")
	if err := os.WriteFile(stage, []byte(body), 0o600); err != nil {
		return "", err
	}
	return stage, nil
}
