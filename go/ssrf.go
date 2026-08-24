package main

// ssrf.go -- endpoint URL validation (port of the Perl _ai_safe_url).
// Allows http(s) only; blocks private / link-local / reserved / multicast
// addresses. Loopback stays allowed (local Ollama, local search, tests).

import (
	"net"
	"strings"
)

// safeURL reports whether url is an http(s) endpoint whose host is not a
// private/link-local/reserved address. allowLoopback permits 127.0.0.1/::1.
func safeURL(raw string, allowLoopback bool) bool {
	raw = strings.TrimSpace(raw)
	low := strings.ToLower(raw)
	if !strings.HasPrefix(low, "http://") && !strings.HasPrefix(low, "https://") {
		return false
	}
	rest := low[len("http://"):]
	if strings.HasPrefix(low, "https://") {
		rest = low[len("https://"):]
	}
	host := rest
	if i := strings.IndexAny(host, "/:"); i >= 0 {
		host = host[:i]
	}
	if host == "" {
		return false
	}
	host = strings.Trim(host, "[]")
	host = strings.TrimPrefix(host, "[")
	host = strings.TrimSuffix(host, "]")
	if host == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	if ip == nil {
		// bare hostname: DNS-level SSRF is not covered here
		return true
	}
	if ip.IsLoopback() {
		return allowLoopback
	}
	if ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() ||
		ip.IsMulticast() || ip.IsUnspecified() || isReserved(ip) {
		return false
	}
	return true
}

// isReserved covers ranges Go's net package does not classify itself:
// 0/8, 100.64/10 (CGNAT), 192.0.2/24 (TEST-NET), 198.18/15, 240+/4.
func isReserved(ip net.IP) bool {
	v4 := ip.To4()
	if v4 == nil {
		return false
	}
	a, b := v4[0], v4[1]
	switch {
	case a == 0:
		return true
	case a == 100 && b >= 64 && b <= 127:
		return true
	case a == 192 && b == 0 && v4[2] == 2:
		return true
	case a == 198 && (b == 18 || b == 19):
		return true
	case a >= 240:
		return true
	}
	return false
}
