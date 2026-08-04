package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/mxxnly/Luna-Agent/internal/agent"
	"github.com/mxxnly/Luna-Agent/internal/bundlepath"
	"github.com/mxxnly/Luna-Agent/internal/version"
)

func main() {
	ensureBrewPath()

	dataDir := flag.String("data-dir", "", "data directory")
	socket := flag.String("socket", "", "ipc socket path")
	enrollURL := flag.String("enroll-url", "", "if set with enroll-code, enroll then exit loops")
	enrollCode := flag.String("enroll-code", "", "enroll code")
	once := flag.Bool("once", false, "run single heartbeat/poll then exit (tests)")
	flag.Parse()

	cfg := agent.Config{
		DataDir:    *dataDir,
		SocketPath: *socket,
		WGDryRun:   os.Getenv("LUNA_WG_DRY_RUN") == "1",
		TestMode:   os.Getenv("LUNA_TEST_MODE") == "1",
	}
	a, err := agent.New(cfg)
	if err != nil {
		log.Fatal(err)
	}
	if err := a.StartIPC(); err != nil {
		log.Fatal(err)
	}
	mode := "live"
	if cfg.WGDryRun {
		mode = "dry-run"
	}
	log.Printf("lunaagentd %s commit=%s socket=%s wg=%s", version.Version, version.Commit, a.SocketPath(), mode)
	logCompat()

	if *enrollURL != "" && *enrollCode != "" {
		if err := a.Enroll(*enrollURL, *enrollCode); err != nil {
			log.Fatalf("enroll: %v", err)
		}
	}

	if *once {
		_ = a.HeartbeatOnce()
		_ = a.PollOnce()
		fmt.Println("ok")
		return
	}

	// Fast command pickup (poll) + moderate metrics reporting (heartbeat).
	go a.RunLoops(15*time.Second, 3*time.Second)

	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
	<-ch
	a.Stop()
}

func ensureBrewPath() {
	// Prefer bundled luna-wg next to the agent when running from the .app.
	_ = os.Setenv("PATH", bundlepath.ToolPATH(os.Getenv("PATH")))
}

func logCompat() {
	ver := "unknown"
	if out, err := exec.Command("sw_vers", "-productVersion").Output(); err == nil {
		ver = strings.TrimSpace(string(out))
	}
	log.Printf("compat os=macOS_%s ui_full_requires=13.0 daemon_min=10.14 features=enroll,vpn,wg,heartbeat,commands,remote", ver)
}
