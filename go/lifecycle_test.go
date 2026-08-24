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

func TestApplyProviderSlot(t *testing.T) {
	cfg := DefaultConfig()
	cfg.Mode = "provider"
	cfg.Endpoint = "https://plan.example/chat"
	cfg.Mode2 = "provider"
	cfg.Endpoint2 = "https://act.example/chat"
	cfg.Model2 = "act-model"

	// default / plan -> slot 1
	eff := applyProviderSlot(cfg, "")
	if eff.Endpoint != "https://plan.example/chat" {
		t.Errorf("plan slot endpoint = %q", eff.Endpoint)
	}
	// act with configured mode2 -> slot 2
	eff = applyProviderSlot(cfg, "act")
	if eff.Endpoint != "https://act.example/chat" || eff.Model != "act-model" {
		t.Errorf("act slot = %q / %q", eff.Endpoint, eff.Model)
	}
	// act with empty mode2 -> falls back to slot 1
	cfg2 := DefaultConfig()
	eff = applyProviderSlot(cfg2, "act")
	if eff.Mode != "free" {
		t.Errorf("empty mode2 should fall back to slot 1, got %q", eff.Mode)
	}
	// act with mode2=off -> falls back to slot 1
	cfg3 := DefaultConfig()
	cfg3.Mode2 = "off"
	eff = applyProviderSlot(cfg3, "act")
	if eff.Mode != "free" {
		t.Errorf("mode2=off should fall back to slot 1, got %q", eff.Mode)
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

