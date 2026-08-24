package main

import (
	"strings"
	"testing"
)

func TestParseAction(t *testing.T) {
	text := "Hier ist die Analyse.\n[[ACTION]]{\"cmd\":\"zfs snapshot tank/data@auto\",\"reason\":\"test\"}[[/ACTION]]"
	clean, action := parseAction(text)
	if action == nil || action.Cmd != "zfs snapshot tank/data@auto" {
		t.Fatalf("action = %+v", action)
	}
	if clean != "Hier ist die Analyse." {
		t.Errorf("clean = %q", clean)
	}
	c2, a2 := parseAction("einfache antwort")
	if a2 != nil || c2 != "einfache antwort" {
		t.Errorf("no action expected: %+v %q", a2, c2)
	}
	// malformed block: keep as-is
	c3, a3 := parseAction("text [[ACTION]]not json[[/ACTION]] ende")
	if a3 != nil {
		t.Errorf("malformed block should not parse: %+v", a3)
	}
	_ = c3
}

func TestExecHint(t *testing.T) {
	cfg := DefaultConfig()
	cfg.ExecAccess = "exec"
	cfg.ExecAllow = []string{"zfs", "zpool", "find"}
	h := execHintFor(cfg)
	if h == "" || !strings.Contains(h, "[[ACTION]]") || !strings.Contains(h, "zfs") {
		t.Errorf("exec hint missing ACTION/classes: %q", h)
	}
	cfg.ExecAccess = "console"
	if !strings.Contains(execHintFor(cfg), "[[ACTION]]") {
		t.Error("console should get an exec hint")
	}
	cfg.ExecAccess = "ro"
	if execHintFor(cfg) != "" {
		t.Error("ro should have no exec hint")
	}
}
