package main

import (
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPIDFilePath(t *testing.T) {
	cfg := &Config{}
	cfg.path = "/opt/csweb-gui/_cfg/cs-aihelp"
	got := pidFilePath(cfg)
	if !strings.HasSuffix(got, "cs-aihelp.pid") {
		t.Fatalf("pidFilePath = %q, want *cs-aihelp.pid", got)
	}
	if runtimeIsWindows() || strings.Contains(strings.ToLower(os.Getenv("GOOS")), "win") {
		want := filepath.Join(filepath.Dir(cfg.path), "cs-aihelp.pid")
		if got != want {
			t.Errorf("pidFilePath = %q, want %q", got, want)
		}
	} else if got != "/var/run/cs-aihelp.pid" {
		t.Errorf("pidFilePath = %q, want /var/run/cs-aihelp.pid", got)
	}
}

func TestPortOpen(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	addr := ln.Addr().String()
	if !portOpen(addr) {
		t.Errorf("portOpen(%s) = false, want true (listener running)", addr)
	}
	if portOpen("127.0.0.1:1") {
		t.Error("portOpen on closed port = true, want false")
	}
}
