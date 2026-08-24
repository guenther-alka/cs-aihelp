package main

import "testing"

func TestSafeURL(t *testing.T) {
	cases := []struct {
		url string
		ok  bool
	}{
		{"https://api.openai.com/v1/chat/completions", true},
		{"http://127.0.0.1:11434/api/chat", true},
		{"http://127.0.0.1:19091/chat", true},
		{"http://192.168.2.10/chat", false},
		{"http://10.0.0.5/chat", false},
		{"http://172.20.0.3/chat", false},
		{"http://169.254.169.254/latest/meta-data", false},
		{"ftp://example.com/x", false},
		{"file:///etc/passwd", false},
		{"http://100.64.1.1/x", false},
		{"http://localhost:8080/chat", true},
	}
	for _, c := range cases {
		if got := safeURL(c.url, true); got != c.ok {
			t.Errorf("safeURL(%q) = %v, want %v", c.url, got, c.ok)
		}
	}
}
