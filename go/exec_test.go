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
	// cs_26.09.06 regression: the model sometimes emits a stray quote before
	// the closing tag ([[ACTION]]{...}"[[/ACTION]]) -- must still parse.
	c4, a4 := parseAction("Ich führe whoami aus.\n[[ACTION]]{\"cmd\":\"whoami\",\"reason\":\"Konto ermitteln\"}\"[[/ACTION]]")
	if a4 == nil || a4.Cmd != "whoami" {
		t.Fatalf("stray-quote action = %+v", a4)
	}
	if !strings.Contains(c4, "Ich führe whoami aus.") || strings.Contains(c4, "[[ACTION]]") {
		t.Errorf("stray-quote clean = %q", c4)
	}
	// both leading and trailing stray quotes
	c5, a5 := parseAction("x [[ACTION]]\"{\"cmd\":\"id\",\"reason\":\"r\"}\"[[/ACTION]] y")
	if a5 == nil || a5.Cmd != "id" {
		t.Fatalf("wrapped-quote action = %+v", a5)
	}
	_ = c5
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
