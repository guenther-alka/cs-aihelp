package main

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestLoadConfigDefaultsAndRoundtrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "cs-aihelp")
	cfg := DefaultConfig()
	cfg.path = path
	cfg.Mode = "provider"
	cfg.Provider = "anthropic"
	cfg.AuthToken = "sekret"
	if err := cfg.Save(); err != nil {
		t.Fatalf("Save: %v", err)
	}
	fi, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	// Unix enforces 0600; Windows does not carry the permission bits.
	if runtime.GOOS != "windows" && fi.Mode().Perm() != 0600 {
		t.Errorf("config perms = %o, want 600", fi.Mode().Perm())
	}
	got, err := LoadConfig(path)
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}
	if got.Mode != "provider" || got.Provider != "anthropic" || got.AuthToken != "sekret" {
		t.Errorf("roundtrip mismatch: %+v", got)
	}
	if got.MaxContext != 8000 || got.Research != "ddg" || got.History != "month" {
		t.Errorf("defaults wrong: %+v", got)
	}
}

func TestLoadConfigCreatesWhenMissing(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing", "cs-aihelp")
	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatalf("LoadConfig missing: %v", err)
	}
	if cfg.Mode != "free" {
		t.Errorf("created config mode = %s, want free", cfg.Mode)
	}
	if _, err := os.Stat(path); err != nil {
		t.Errorf("config was not created: %v", err)
	}
}
