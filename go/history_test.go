package main

import (
	"path/filepath"
	"testing"
	"time"
)

// newestConv must return the newest conversation of the member, ignoring
// other members, and fall back through older entries.
func TestNewestConv(t *testing.T) {
	base := filepath.Join(t.TempDir(), "csweb-gui")
	now := time.Now().Unix()
	saveConv(base, "old_1", &Conversation{Created: now - 100, Updated: now - 100, Member: "m2~10.0.0.2", Title: "other"})
	saveConv(base, "new_1", &Conversation{Created: now - 50, Updated: now - 50, Member: "m1~10.0.0.1", Title: "my conv"})
	saveConv(base, "new_2", &Conversation{Created: now - 10, Updated: now - 10, Member: "m1~10.0.0.1", Title: "my newest"})

	id, conv := newestConv(base, "m1~10.0.0.1")
	if id != "new_2" {
		t.Fatalf("expected new_2, got %q", id)
	}
	if conv == nil || conv.Title != "my newest" {
		t.Fatalf("unexpected conv: %+v", conv)
	}

	if _, c := newestConv(base, "nobody~nohost"); c != nil {
		t.Fatalf("expected nil for unknown member")
	}
}
