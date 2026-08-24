package main

// cmd.go -- CLI subcommands: serve / ask / status / stop / reindex.

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

func cswebBase(cfg *Config) string {
	p := cfg.path
	if i := strings.Index(p, "/csweb-gui/_cfg"); i >= 0 {
		return p[:i+len("/csweb-gui")]
	}
	return "/opt/csweb-gui"
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
	if err := app.Serve(foreground); err != nil {
		fmt.Fprintln(os.Stderr, "serve:", err)
		os.Exit(1)
	}
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
	if _, err := LoadConfig(path); err != nil {
		fmt.Fprintln(os.Stderr, "config:", err)
		os.Exit(2)
	}
	pidf := "/var/run/cs-aihelp.pid"
	if b, err := os.ReadFile(pidf); err == nil {
		if pid, err := strconv.Atoi(strings.TrimSpace(string(b))); err == nil {
			if p, err := os.FindProcess(pid); err == nil {
				if err := p.Signal(os.Interrupt); err == nil {
					fmt.Println("stopped pid", pid)
					return
				}
			}
		}
	}
	fmt.Fprintln(os.Stderr, "no pid file; stop the daemon via its supervisor (e.g. autostart.pl)")
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
