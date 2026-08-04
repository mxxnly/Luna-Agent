package metrics

import (
	"os"
	"os/exec"
	"runtime"
	"sort"
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

// Snapshot collects host CPU/RAM/disk usage as percentages plus process samples.
func Snapshot() api.MetricsSnapshot {
	ramUsed, ramTotal := hostRAM()
	diskUsed, diskTotal := hostDisk("/")
	cpu := hostCPUPct()
	snap := api.MetricsSnapshot{
		CPUPct:         clampPct(cpu),
		RAMPct:         pct(ramUsed, ramTotal),
		DiskPct:        pct(diskUsed, diskTotal),
		RAMUsedBytes:   ramUsed,
		RAMTotalBytes:  ramTotal,
		DiskUsedBytes:  diskUsed,
		DiskTotalBytes: diskTotal,
		TopCPU:         topProcesses(10, true),
		TopRAM:         topProcesses(10, false),
	}
	_ = time.Now()
	return snap
}

func pct(used, total int64) float64 {
	if total <= 0 {
		return 0
	}
	return clampPct(100 * float64(used) / float64(total))
}

func clampPct(v float64) float64 {
	if v < 0 {
		return 0
	}
	if v > 100 {
		return 100
	}
	return v
}

func hostCPUPct() float64 {
	ncpu := float64(runtime.NumCPU())
	if ncpu < 1 {
		ncpu = 1
	}
	// Sum of per-core %cpu from ps ≈ system load relative to all cores.
	out, err := exec.Command("/bin/ps", "-A", "-o", "%cpu=").Output()
	if err != nil {
		return 0
	}
	var sum float64
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		v, err := strconv.ParseFloat(line, 64)
		if err != nil {
			continue
		}
		sum += v
	}
	return sum / ncpu
}

func hostRAM() (used, total int64) {
	if runtime.GOOS == "darwin" {
		total = parseInt64(strings.TrimSpace(runOut("/usr/sbin/sysctl", "-n", "hw.memsize")))
		if total <= 0 {
			total = parseInt64(strings.TrimSpace(runOut("sysctl", "-n", "hw.memsize")))
		}
		if u := darwinMemUsed(); u > 0 {
			used = u
			if total > 0 && used > total {
				used = total
			}
			return used, total
		}
	}
	var ms runtime.MemStats
	runtime.ReadMemStats(&ms)
	if total == 0 {
		total = int64(ms.Sys)
	}
	used = int64(ms.Alloc)
	return used, total
}

func darwinMemUsed() int64 {
	// Approx Activity Monitor "Memory Used": active + wired + compressor.
	pageSize := parseInt64(strings.TrimSpace(runOut("/usr/bin/pagesize")))
	if pageSize <= 0 {
		pageSize = parseInt64(strings.TrimSpace(runOut("pagesize")))
	}
	if pageSize <= 0 {
		pageSize = 16384
	}
	out := runOut("/usr/bin/vm_stat")
	if out == "" {
		out = runOut("vm_stat")
	}
	var active, wired, compressed int64
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(line, "Pages active"):
			active = vmStatPages(line)
		case strings.HasPrefix(line, "Pages wired"):
			wired = vmStatPages(line)
		case strings.HasPrefix(line, "Pages occupied by compressor"):
			compressed = vmStatPages(line)
		case strings.HasPrefix(line, "Pages stored in compressor"):
			if compressed == 0 {
				compressed = vmStatPages(line)
			}
		}
	}
	pages := active + wired + compressed
	if pages <= 0 {
		return 0
	}
	return pages * pageSize
}

func vmStatPages(line string) int64 {
	// "Pages active:                  123456."
	parts := strings.Split(line, ":")
	if len(parts) < 2 {
		return 0
	}
	num := strings.TrimSpace(parts[1])
	num = strings.TrimSuffix(num, ".")
	num = strings.ReplaceAll(num, ",", "")
	return parseInt64(num)
}

func hostDisk(path string) (used, total int64) {
	if runtime.GOOS == "darwin" {
		// `/` is often the sealed system snapshot; user-facing capacity lives on Data.
		if path == "/" {
			if u, t := hostDiskDF("/System/Volumes/Data"); t > 0 {
				return u, t
			}
		}
	}
	return hostDiskDF(path)
}

func hostDiskDF(path string) (used, total int64) {
	out, err := exec.Command("/bin/df", "-k", path).Output()
	if err != nil {
		out, err = exec.Command("df", "-k", path).Output()
		if err != nil {
			return 0, 0
		}
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	if len(lines) < 2 {
		return 0, 0
	}
	fields := strings.Fields(lines[len(lines)-1])
	// Filesystem 1024-blocks Used Available Capacity ...
	if len(fields) < 4 {
		return 0, 0
	}
	totalK := parseInt64(fields[1])
	usedK := parseInt64(fields[2])
	return usedK * 1024, totalK * 1024
}

func parseInt64(s string) int64 {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	v, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0
	}
	return v
}

func topProcesses(n int, byCPU bool) []api.ProcessSample {
	if runtime.GOOS != "darwin" && runtime.GOOS != "linux" {
		return nil
	}
	out, err := exec.Command("/bin/ps", "-axo", "pid=,user=,pcpu=,rss=,comm=").Output()
	if err != nil {
		return nil
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	samples := make([]api.ProcessSample, 0, len(lines))
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
	}
	sort.Slice(samples, func(i, j int) bool {
		if byCPU {
			return samples[i].CPUPct > samples[j].CPUPct
		}
		return samples[i].RAMBytes > samples[j].RAMBytes
	})
	if len(samples) > n {
		samples = samples[:n]
	}
	return samples
}

// HostInfo gathers basic device inventory.
func HostInfo() api.HardwareInfo {
	host, _ := os.Hostname()
	user := os.Getenv("USER")
	serial := readIOPlatformKey("IOPlatformSerialNumber")
	if serial == "" {
		serial = "unknown"
	}
	return api.HardwareInfo{
		Hostname:     host,
		Model:        readSysctl("hw.model"),
		Serial:       serial,
		HardwareUUID: readIOPlatformKey("IOPlatformUUID"),
		OSVersion:    osVersionString(),
		Username:     user,
	}
}

func osVersionString() string {
	if runtime.GOOS == "darwin" {
		product := strings.TrimSpace(runOut("sw_vers", "-productVersion"))
		build := strings.TrimSpace(runOut("sw_vers", "-buildVersion"))
		arch := runtime.GOARCH
		if product != "" {
			if build != "" {
				return "macOS " + product + " (" + build + ") " + arch
			}
			return "macOS " + product + " " + arch
		}
	}
	return runtime.GOOS + "/" + runtime.GOARCH
}

func runOut(name string, args ...string) string {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		return ""
	}
	return string(out)
}

func readSysctl(name string) string {
	return strings.TrimSpace(runOut("sysctl", "-n", name))
}

func readIOPlatformKey(key string) string {
	out, err := exec.Command("ioreg", "-rd1", "-c", "IOPlatformExpertDevice").Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(out), "\n") {
		if strings.Contains(line, key) {
			parts := strings.Split(line, "\"")
			if len(parts) >= 4 {
				return parts[len(parts)-2]
			}
		}
	}
	return ""
}
