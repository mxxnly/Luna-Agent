package metrics

import (
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/mxxnly/Luna-Agent/internal/api"
)

// SanitizeCmdline strips likely secrets from process arguments.
func SanitizeCmdline(s string) string {
	parts := strings.Fields(s)
	out := make([]string, 0, len(parts))
	for i := 0; i < len(parts); i++ {
		p := parts[i]
		lower := strings.ToLower(p)
		if strings.Contains(lower, "token") || strings.Contains(lower, "password") ||
			strings.Contains(lower, "secret") || strings.HasPrefix(lower, "privatekey") {
			out = append(out, "[redacted]")
			continue
		}
		if (strings.HasPrefix(p, "--") || strings.HasPrefix(p, "-")) && i+1 < len(parts) {
			flag := lower
			if strings.Contains(flag, "token") || strings.Contains(flag, "pass") || strings.Contains(flag, "key") {
				out = append(out, p, "[redacted]")
				i++
				continue
			}
		}
		out = append(out, p)
	}
	return strings.Join(out, " ")
}

// Snapshot collects a best-effort metrics snapshot (portable enough for CI).
func Snapshot() api.MetricsSnapshot {
	var ms runtime.MemStats
	runtime.ReadMemStats(&ms)
	snap := api.MetricsSnapshot{
		CPUPct:         float64(runtime.NumCPU()), // placeholder load indicator; refined later
		RAMUsedBytes:   int64(ms.Alloc),
		RAMTotalBytes:  int64(ms.Sys),
		DiskUsedBytes:  0,
		DiskTotalBytes: 0,
		TopCPU:         topProcesses(10),
		TopRAM:         topProcesses(10),
	}
	_ = time.Now()
	return snap
}

func topProcesses(n int) []api.ProcessSample {
	if runtime.GOOS != "darwin" && runtime.GOOS != "linux" {
		return nil
	}
	cmd := exec.Command("ps", "-axo", "pid=,user=,pcpu=,rss=,comm=")
	out, err := cmd.Output()
	if err != nil {
		return nil
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	samples := make([]api.ProcessSample, 0, n)
	for _, line := range lines {
		fields := strings.Fields(line)
		if len(fields) < 5 {
			continue
		}
		pid, _ := strconv.Atoi(fields[0])
		cpu, _ := strconv.ParseFloat(fields[2], 64)
		rssKB, _ := strconv.ParseInt(fields[3], 10, 64)
		name := SanitizeCmdline(strings.Join(fields[4:], " "))
		samples = append(samples, api.ProcessSample{
			PID:      pid,
			Name:     name,
			User:     fields[1],
			CPUPct:   cpu,
			RAMBytes: rssKB * 1024,
		})
		if len(samples) >= n {
			break
		}
	}
	return samples
}

// HostInfo gathers basic device inventory.
func HostInfo() api.HardwareInfo {
	host, _ := os.Hostname()
	user := os.Getenv("USER")
	return api.HardwareInfo{
		Hostname:     host,
		Model:        readSysctl("hw.model"),
		Serial:       "unknown",
		HardwareUUID: readIOPlatformUUID(),
		OSVersion:    runtime.GOOS + "/" + runtime.GOARCH,
		Username:     user,
	}
}

func readSysctl(name string) string {
	out, err := exec.Command("sysctl", "-n", name).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func readIOPlatformUUID() string {
	out, err := exec.Command("ioreg", "-rd1", "-c", "IOPlatformExpertDevice").Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(out), "\n") {
		if strings.Contains(line, "IOPlatformUUID") {
			parts := strings.Split(line, "\"")
			if len(parts) >= 4 {
				return parts[len(parts)-2]
			}
		}
	}
	return ""
}
