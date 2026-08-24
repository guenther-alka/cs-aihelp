package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRagRetrieve(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "smb-nfs.info"), []byte(
		"# SMB\nSMB shares are managed under Filesystems.\nCreate a share and set ACLs.\n"), 0600)
	os.WriteFile(filepath.Join(dir, "jobs.info"), []byte(
		"# Jobs\nSnap jobs are scheduled under the Jobs menu.\n"), 0600)
	os.WriteFile(filepath.Join(dir, "_skip.txt"), []byte("ignored"), 0600)

	idx := NewRagIndex(dir)
	if err := idx.Rebuild(); err != nil {
		t.Fatalf("Rebuild: %v", err)
	}
	if idx.IndexedDocs() != 2 {
		t.Errorf("indexed = %d, want 2", idx.IndexedDocs())
	}
	docs := idx.Retrieve("wie aktiviere ich smb shares", 4)
	if len(docs) == 0 {
		t.Fatal("no docs retrieved for smb question")
	}
	if docs[0].File != "smb-nfs.info" {
		t.Errorf("top hit = %s, want smb-nfs.info", docs[0].File)
	}
	if docs[0].Snippet == "" {
		t.Error("snippet empty")
	}
}
