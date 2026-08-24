package main

// config.go -- key = value config, shared with the Perl frontend
// (_cfg/cs-aihelp). Unknown keys are ignored (forward compatible); the
// daemon-side network keys (listen/allowed_ip/auth_token/tls_*/cors_origin)
// are also read from the same file.

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type Config struct {
	// provider / AI
	Mode       string // off | free | provider
	Provider   string // openai | anthropic | ollama
	Endpoint   string // full chat-completions/messages URL ('' = default)
	Model      string // '' = provider default
	APIKey     string
	FreeModel  string // mode=free: local Ollama model tag ('' = first)
	Fallback   string // off | free
	ToolUse    bool
	MaxContext int

	// research
	Research    string // off | ddg | api
	ResearchMax int
	ResearchEP  string // api mode: URL template with {q}
	ResearchKey string

	// history
	History      string // off|today|week|month|6months|all
	HistoryTurns int

	// ui
	Widget   bool
	Log      bool

	// security
	SSRFAllowPrivate bool // yes = allow RFC1918/private endpoints (LAN-only)
	RateLimit        int  // max requests/min per client IP in the daemon (0 = off)

	// level 2 / exec
	ExecAccess string   // ro | exec | console
	ExecMode   string   // propose | confirm | auto (used when ExecAccess != ro)
	ExecAllow  []string // D2 command classes/prefixes; empty = nothing allowed
	ExecDeny   []string // always applied, wins

	// ui / popup
	WidgetInputLines  int
	WidgetAnswerHeight int

	// daemon / network
	Listen     string // 127.0.0.1:45555 (default) | 0.0.0.0:45555
	AllowedIP  string // comma-separated IP/CIDR; empty = loopback only; "*" = any
	AuthToken  string // bearer token; required when Listen is not loopback
	TLSCert    string
	TLSKey     string
	CORSOrigin string

	path string
}

func DefaultConfig() *Config {
	return &Config{
		Mode: "free", Provider: "openai", Fallback: "free",
		ToolUse: false, MaxContext: 8000,
		Research: "ddg", ResearchMax: 5,
		History: "month", HistoryTurns: 10,
		Widget: true, Log: true,
		SSRFAllowPrivate: false, RateLimit: 60,
		ExecAccess: "ro", ExecMode: "confirm",
		WidgetInputLines: 1, WidgetAnswerHeight: 220,
		Listen:  "127.0.0.1:45555",
		TLSCert: "/opt/csweb-gui/_cfg/webserver/cert/server.crt",
		TLSKey:  "/opt/csweb-gui/_cfg/webserver/cert/server.key",
	}
}

func defaultConfigPath() string {
	if p := os.Getenv("CS_AIHELP_CONFIG"); p != "" {
		return p
	}
	return "/opt/csweb-gui/_cfg/cs-aihelp"
}

// splitList splits on sep, trims and drops empties.
func splitList(s, sep string) []string {
	var out []string
	for _, p := range strings.Split(s, sep) {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func LoadConfig(path string) (*Config, error) {
	cfg := DefaultConfig()
	cfg.path = path
	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			if e := cfg.Save(); e != nil {
				return nil, e
			}
			return cfg, nil
		}
		return nil, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		kv := strings.SplitN(line, "=", 2)
		if len(kv) != 2 {
			continue
		}
		k := strings.TrimSpace(kv[0])
		v := strings.TrimSpace(kv[1])
		switch k {
		case "mode":
			cfg.Mode = v
		case "provider":
			cfg.Provider = v
		case "endpoint":
			cfg.Endpoint = v
		case "model":
			cfg.Model = v
		case "api_key":
			cfg.APIKey = v
		case "free_model":
			cfg.FreeModel = v
		case "fallback":
			cfg.Fallback = v
		case "tool_use":
			cfg.ToolUse = v == "yes"
		case "max_context":
			fmt.Sscanf(v, "%d", &cfg.MaxContext)
		case "research":
			cfg.Research = v
		case "research_max":
			fmt.Sscanf(v, "%d", &cfg.ResearchMax)
		case "research_endpoint":
			cfg.ResearchEP = v
		case "research_key":
			cfg.ResearchKey = v
		case "history":
			cfg.History = v
		case "history_turns":
			fmt.Sscanf(v, "%d", &cfg.HistoryTurns)
		case "widget":
			cfg.Widget = v == "on" || v == "yes"
		case "log":
			cfg.Log = v != "off"
		case "ssrf_allow_private":
			cfg.SSRFAllowPrivate = v == "yes" || v == "on"
		case "rate_limit":
			fmt.Sscanf(v, "%d", &cfg.RateLimit)
		case "exec_access":
			cfg.ExecAccess = v
		case "exec_mode":
			cfg.ExecMode = v
		case "exec_allow":
			cfg.ExecAllow = splitList(v, ",")
		case "exec_deny":
			cfg.ExecDeny = splitList(v, "|")
		case "widget_input_lines":
			fmt.Sscanf(v, "%d", &cfg.WidgetInputLines)
		case "widget_answer_height":
			fmt.Sscanf(v, "%d", &cfg.WidgetAnswerHeight)
		case "listen":
			cfg.Listen = v
		case "allowed_ip":
			cfg.AllowedIP = v
		case "auth_token":
			cfg.AuthToken = v
		case "tls_cert":
			cfg.TLSCert = v
		case "tls_key":
			cfg.TLSKey = v
		case "cors_origin":
			cfg.CORSOrigin = v
		}
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if cfg.MaxContext <= 0 {
		cfg.MaxContext = 8000
	}
	if cfg.ResearchMax <= 0 {
		cfg.ResearchMax = 5
	}
	if cfg.HistoryTurns <= 0 {
		cfg.HistoryTurns = 10
	}
	if cfg.RateLimit < 0 {
		cfg.RateLimit = 60
	}
	return cfg, nil
}

// Save writes the full config with defaults for missing keys, mode 0600.
func (c *Config) Save() error {
	if c.path == "" {
		c.path = defaultConfigPath()
	}
	if err := os.MkdirAll(filepath.Dir(c.path), 0700); err != nil {
		return err
	}
	var b strings.Builder
	b.WriteString("# cs-aihelp configuration -- see data/howto.ai/ai-helpdesk.info\n")
	b.WriteString("# Written by cs-aihelp (Go daemon / csweb-gui Settings).\n")
	b.WriteString("# DO NOT SHARE: api_key and auth_token are secrets.\n\n")
	fw := func(k, v string) { fmt.Fprintf(&b, "%-14s = %s\n", k, v) }
	yn := func(v bool) string {
		if v {
			return "yes"
		}
		return "no"
	}
	fw("mode", c.Mode)
	fw("provider", c.Provider)
	fw("endpoint", c.Endpoint)
	fw("model", c.Model)
	fw("api_key", c.APIKey)
	fw("free_model", c.FreeModel)
	fw("fallback", c.Fallback)
	fw("tool_use", yn(c.ToolUse))
	fw("max_context", fmt.Sprintf("%d", c.MaxContext))
	fw("research", c.Research)
	fw("research_max", fmt.Sprintf("%d", c.ResearchMax))
	fw("research_endpoint", c.ResearchEP)
	fw("research_key", c.ResearchKey)
	fw("history", c.History)
	fw("history_turns", fmt.Sprintf("%d", c.HistoryTurns))
	fw("widget", yn(c.Widget))
	fw("exec_mode", c.ExecMode)
	fw("log", yn(c.Log))
	fw("ssrf_allow_private", yn(c.SSRFAllowPrivate))
	fw("rate_limit", fmt.Sprintf("%d", c.RateLimit))
	fw("exec_access", c.ExecAccess)
	fw("exec_allow", strings.Join(c.ExecAllow, ","))
	fw("exec_deny", strings.Join(c.ExecDeny, "|"))
	fw("widget_input_lines", fmt.Sprintf("%d", c.WidgetInputLines))
	fw("widget_answer_height", fmt.Sprintf("%d", c.WidgetAnswerHeight))
	fw("listen", c.Listen)
	fw("allowed_ip", c.AllowedIP)
	fw("auth_token", c.AuthToken)
	fw("tls_cert", c.TLSCert)
	fw("tls_key", c.TLSKey)
	fw("cors_origin", c.CORSOrigin)
	return os.WriteFile(c.path, []byte(b.String()), 0600)
}
