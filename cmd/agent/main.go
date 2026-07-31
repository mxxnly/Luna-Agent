package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/mxxnly/Luna-Agent/internal/agent"
	"github.com/mxxnly/Luna-Agent/internal/version"
)

func main() {
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
	log.Printf("lunaagentd %s commit=%s socket=%s", version.Version, version.Commit, a.SocketPath())

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

	go a.RunLoops(30*time.Second, 15*time.Second)

	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
	<-ch
	a.Stop()
}
