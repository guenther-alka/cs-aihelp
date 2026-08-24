package main

// cmd.go -- CLI subcommands: serve / ask / status / stop / reindex.

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func cswebBase(cfg *Config) string {
	p := cfg.path
	if i := strings.Index(p, "/csweb-gui/_cfg"); i >= 0 {
		return p[:i+len("/csweb-gui")]
	}
	return "/opt/csweb-gui"
}

// pidFilePath is the deterministic location of the daemon PID file.
// Windows: next to the config file (_cfg/cs-aihelp.pid) -- always writable
// and stable regardless of how the config path is spelled. Unix: /var/run
// (napp-it runs as root).
func pidFilePath(cfg *Config) string {
	if runtimeIsWindows() {
		return filepath.Join(filepath.Dir(cfg.path), "cs-aihelp.pid")
	}
	return "/var/run/cs-aihelp.pid"
}

func writePID(cfg *Config) {
	p := pidFilePath(cfg)
	if dir := filepath.Dir(p); dir != "" {
		os.MkdirAll(dir, 0755)
	}
	if f, err := os.Create(p); err == nil {
		fmt.Fprintf(f, "%d\n", os.Getpid())
		f.Close()
		return
	}
	fmt.Fprintln(os.Stderr, "warning: cannot write pid file", p)
}

func removePID(cfg *Config) {
	os.Remove(pidFilePath(cfg))
}

// portOpen reports whether something already listens on addr (idempotence
// check for `start`). A plain TCP dial succeeds regardless of TLS.
func portOpen(addr string) bool {
	conn, err := net.DialTimeout("tcp", addr, 1200*time.Millisecond)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func serveCmd(args []string) {
	path, rest, err := parseFlags(args)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	cfg, err := LoadConfig(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "config:", err)
		os.Exit(2)
	}
	if v, ok := rest["listen"]; ok && v != "" {
		cfg.Listen = v
	}
	foreground := rest["foreground"] == "true" || rest["foreground"] == "1"
	app := NewApp(cfg, cswebBase(cfg))
	if err := app.Reindex(); err != nil {
		fmt.Fprintln(os.Stderr, "reindex:", err)
	}
	if !foreground && os.Getenv("CS_AIHELP_DAEMONIZED") == "" {
		daemonize()
	}
	// we are the daemon process now -- own the PID file and clean up on
	// SIGINT (Unix; `cs-aihelp stop`) or taskkill /F (Windows)
	writePID(cfg)
	defer removePID(cfg)
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt)
	go func() {
		<-sig
		removePID(cfg)
		os.Exit(0)
	}()
	if err := app.Serve(foreground); err != nil {
		fmt.Fprintln(os.Stderr, "serve:", err)
		os.Exit(1)
	}
}

// startCmd launches the daemon detached and is idempotent: if the listen
// port is already taken it prints a notice and returns 0. Used by
// server.pl's boot hook (server_boot_tasks.pl).
func startCmd(args []string) {
	path, _, err := parseFlags(args)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	cfg, err := LoadConfig(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "config:", err)
		os.Exit(2)
	}
	if portOpen(cfg.Listen) {
		fmt.Println("cs-aihelp already running on", cfg.Listen)
		return
	}
	exe, err := os.Executable()
	if err != nil {
		fmt.Fprintln(os.Stderr, "cannot resolve executable:", err)
		os.Exit(2)
	}
	if runtimeIsWindows() {
		// Windows: detached via PowerShell Start-Process (hidden window).
		// The daemon runs in the foreground of that hidden process; the
		// PID file is written by the daemon itself.
		ps := exec.Command("powershell", "-NoProfile", "-Command",
			"Start-Process -WindowStyle Hidden -FilePath '"+exe+"' -ArgumentList 'serve','--config','"+path+"'")
		ps.Stdout = os.Stdout
		ps.Stderr = os.Stderr
		if err := ps.Run(); err != nil {
			fmt.Fprintln(os.Stderr, "start failed:", err)
			os.Exit(1)
		}
	} else {
		// Unix: nohup keeps the daemon alive after this process exits.
		// CS_AIHELP_DAEMONIZED=1 prevents serveCmd from re-daemonizing.
		cmd := exec.Command("nohup", exe, "serve", "--config", path)
		cmd.Env = append(os.Environ(), "CS_AIHELP_DAEMONIZED=1")
		cmd.Stdout = nil
		cmd.Stderr = nil
		if err := cmd.Start(); err != nil {
			fmt.Fprintln(os.Stderr, "start failed:", err)
			os.Exit(1)
		}
	}
	fmt.Println("cs-aihelp started (pid file: " + pidFilePath(cfg) + ")")
}

func askCmd(args []string) {
	path, rest, err := parseFlags(args)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	q := rest["question"]
	if q == "" {
		fmt.Fprintln(os.Stderr, "error: --question required")
		os.Exit(2)
	}
	cfg, err := LoadConfig(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "config:", err)
		os.Exit(2)
	}
	app := NewApp(cfg, cswebBase(cfg))
	if err := app.Reindex(); err != nil {
		fmt.Fprintln(os.Stderr, "reindex:", err)
	}
	res, err := app.Ask(AskRequest{Question: q}, "cli")
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
	if rest["json"] == "true" {
		json.NewEncoder(os.Stdout).Encode(res)
		return
	}
	fmt.Println(res.Answer)
}

func statusCmd(args []string) {
	path, rest, _ := parseFlags(args)
	cfg, err := LoadConfig(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "config:", err)
		os.Exit(2)
	}
	app := NewApp(cfg, cswebBase(cfg))
	if err := app.Reindex(); err != nil {
		fmt.Fprintln(os.Stderr, "reindex:", err)
	}
	st := map[string]any{
		"version": version, "mode": cfg.Mode, "listen": cfg.Listen,
		"convos": len(listConvs(cswebBase(cfg))), "indexed": app.rag.IndexedDocs(),
	}
	if rest["json"] == "true" {
		json.NewEncoder(os.Stdout).Encode(st)
		return
	}
	fmt.Printf("cs-aihelp %s\n  mode=%s listen=%s convos=%v docs=%v\n",
		version, cfg.Mode, cfg.Listen, st["convos"], st["indexed"])
}

func stopCmd(args []string) {
	path, _, _ := parseFlags(args)
	cfg, err := LoadConfig(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "config:", err)
		os.Exit(2)
	}
	pidf := pidFilePath(cfg)
	b, err := os.ReadFile(pidf)
	if err != nil {
		fmt.Fprintln(os.Stderr, "no pid file at "+pidf+"; nothing to stop")
		os.Exit(1)
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil {
		fmt.Fprintln(os.Stderr, "bad pid in", pidf)
		os.Exit(1)
	}
	if runtimeIsWindows() {
		// Windows has no Unix signals -- use taskkill /F
		out, kerr := exec.Command("taskkill", "/PID", strconv.Itoa(pid), "/F").CombinedOutput()
		if kerr != nil {
			fmt.Fprintln(os.Stderr, "taskkill:", string(out))
			os.Exit(1)
		}
		fmt.Println("stopped pid", pid)
	} else {
		p, perr := os.FindProcess(pid)
		if perr != nil {
			fmt.Fprintln(os.Stderr, "find process:", perr)
			os.Exit(1)
		}
		if serr := p.Signal(os.Interrupt); serr != nil {
			fmt.Fprintln(os.Stderr, "signal:", serr)
			os.Exit(1)
		}
		fmt.Println("stopped pid", pid)
	}
	os.Remove(pidf)
}

func reindexCmd(args []string) {
	path, _, _ := parseFlags(args)
	cfg, err := LoadConfig(path)
	if err != nil {
		fmt.Fprintln(os.Stderr, "config:", err)
		os.Exit(2)
	}
	app := NewApp(cfg, cswebBase(cfg))
	if err := app.Reindex(); err != nil {
		fmt.Fprintln(os.Stderr, "reindex:", err)
		os.Exit(1)
	}
	fmt.Printf("indexed %d docs from %s\n", app.rag.IndexedDocs(), cswebBase(cfg)+"/data/howto.ai")
}

// daemonize re-execs itself in the background on Unix-like systems; on
// Windows the daemon runs in the foreground (use a service/scheduled start).
func daemonize() {
	if strings.EqualFold(os.Getenv("GOOS"), "windows") || runtimeIsWindows() {
		return
	}
	exe, err := os.Executable()
	if err != nil {
		return
	}
	cmd := exec.Command(exe, os.Args[1:]...)
	cmd.Env = append(os.Environ(), "CS_AIHELP_DAEMONIZED=1")
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Start(); err == nil {
		fmt.Println("cs-aihelp daemonized pid", cmd.Process.Pid)
		os.Exit(0)
	}
}

func runtimeIsWindows() bool {
	return strings.Contains(strings.ToLower(os.Getenv("GOOS")), "win") || os.PathSeparator == '\\'
}
