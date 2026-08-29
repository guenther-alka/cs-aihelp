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

	// default / p1 -> slot 1
	eff, err := applyProviderSlot(cfg, "")
	if err != nil {
		t.Fatal(err)
	}
	if eff.Endpoint != "https://plan.example/chat" {
		t.Errorf("p1 slot endpoint = %q", eff.Endpoint)
	}
	// p2 with configured mode2 -> slot 2
	eff, err = applyProviderSlot(cfg, "p2")
	if err != nil {
		t.Fatal(err)
	}
	if eff.Endpoint != "https://act.example/chat" || eff.Model != "act-model" {
		t.Errorf("p2 slot = %q / %q", eff.Endpoint, eff.Model)
	}
	// p2 with empty mode2 -> falls back to slot 1
	cfg2 := DefaultConfig()
	eff, err = applyProviderSlot(cfg2, "p2")
	if err != nil {
		t.Fatal(err)
	}
	if eff.Mode != "free" {
		t.Errorf("empty mode2 should fall back to slot 1, got %q", eff.Mode)
	}
	// p2 with mode2=off -> falls back to slot 1
	cfg3 := DefaultConfig()
	cfg3.Mode2 = "off"
	eff, err = applyProviderSlot(cfg3, "p2")
	if err != nil {
		t.Fatal(err)
	}
	if eff.Mode != "free" {
		t.Errorf("mode2=off should fall back to slot 1, got %q", eff.Mode)
	}
	// p3 with configured mode3 -> slot 3
	cfg4 := DefaultConfig()
	cfg4.Mode3 = "provider"
	cfg4.Endpoint3 = "https://vision.example/chat"
	cfg4.Model3 = "vision-model"
	eff, err = applyProviderSlot(cfg4, "p3")
	if err != nil {
		t.Fatal(err)
	}
	if eff.Endpoint != "https://vision.example/chat" || eff.Model != "vision-model" {
		t.Errorf("p3 slot = %q / %q", eff.Endpoint, eff.Model)
	}
	// p3 with empty mode3 -> "not configured" error (no fallback to slot 1)
	if _, err = applyProviderSlot(DefaultConfig(), "p3"); err == nil {
		t.Errorf("p3 with empty mode3 should error, got nil")
	}
	// p3 with mode3=off -> "not configured" error (no fallback to slot 1)
	cfg5 := DefaultConfig()
	cfg5.Mode3 = "off"
	if _, err = applyProviderSlot(cfg5, "p3"); err == nil {
		t.Errorf("p3 with mode3=off should error, got nil")
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

