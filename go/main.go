package main

// cs-aihelp -- AI Helpdesk daemon + CLI for napp-it cs.
//
// Usage:
//   cs-aihelp serve   [--listen ADDR] [--config PATH] [--foreground]
//   cs-aihelp start   [--config PATH]   (detached + idempotent)
//   cs-aihelp ask     --question "..."
//   cs-aihelp status  [--config PATH] [--json]
//   cs-aihelp stop    [--config PATH]
//   cs-aihelp reindex [--config PATH]
//   cs-aihelp version

import (
	"fmt"
	"os"
	"strings"
)

var version = "1.1.1"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}
	switch os.Args[1] {
	case "version":
		fmt.Println("cs-aihelp " + version)
	case "serve":
		serveCmd(os.Args[2:])
	case "start":
		startCmd(os.Args[2:])
	case "ask":
		askCmd(os.Args[2:])
	case "status":
		statusCmd(os.Args[2:])
	case "stop":
		stopCmd(os.Args[2:])
	case "reindex":
		reindexCmd(os.Args[2:])
	case "help", "-h", "--help":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n\n", os.Args[1])
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Println(`cs-aihelp -- AI Helpdesk daemon for napp-it cs (` + version + `)

Usage:
  cs-aihelp serve   [--listen ADDR] [--config PATH] [--foreground]
  cs-aihelp start   [--config PATH]   (detached + idempotent; for boot hooks)
  cs-aihelp ask     --question "..." [--config PATH] [--json]
  cs-aihelp status  [--config PATH] [--json]
  cs-aihelp stop    [--config PATH]   (reads the daemon PID file)
  cs-aihelp reindex [--config PATH]
  cs-aihelp version

Config:
  default /opt/csweb-gui/_cfg/cs-aihelp (key = value, shared with the
  web-GUI Settings menu); override with --config or env CS_AIHELP_CONFIG.

  listen      = 127.0.0.1:45555   # remote: 0.0.0.0:45555 (then auth_token required)
  allowed_ip  =                   # empty=loopback; IP/CIDR list; *=any
  auth_token  =                   # bearer token (required for remote listen)
  tls_cert    = /opt/csweb-gui/_cfg/webserver/cert/server.crt
  tls_key     = /opt/csweb-gui/_cfg/webserver/cert/server.key
  cors_origin =                   # optional frontend origin (CORS pinning)
  mode / provider / endpoint / model / api_key / free_model / fallback /
  tool_use / max_context / research / research_max / research_endpoint /
  research_key / history / history_turns / widget / exec_mode / log

Endpoints (serve):
  GET  /health /status /sources?q= /models
  POST /ask      (JSON or stream=true -> SSE)
  POST /reload /reindex`)
}

// parseFlags extracts --config and returns remaining -flag=value pairs.
// Manual, permissive parser (each subcommand accepts its own flag set).
func parseFlags(args []string) (path string, rest map[string]string, err error) {
	rest = map[string]string{}
	path = defaultConfigPath()
	for i := 0; i < len(args); i++ {
		a := args[i]
		if !strings.HasPrefix(a, "-") {
			continue
		}
		kv := strings.TrimLeft(a, "-")
		key, val := kv, ""
		hasEq := false
		if j := strings.Index(kv, "="); j >= 0 {
			key, val, hasEq = kv[:j], kv[j+1:], true
		}
		if key == "config" {
			if hasEq {
				path = val
			} else if i+1 < len(args) {
				i++
				path = args[i]
			}
			continue
		}
		if !hasEq {
			// value-taking flags consume the next argument; booleans -> "true"
			if (key == "question" || key == "listen") && i+1 < len(args) && !strings.HasPrefix(args[i+1], "-") {
				i++
				val = args[i]
			} else {
				val = "true"
			}
		}
		rest[key] = val
	}
	return path, rest, nil
}
