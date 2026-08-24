package main

// research.go -- web research: DuckDuckGo Lite (no key) + generic JSON API.
// URL/title/snippet results, SSRF-guarded.

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"
)

type SearchResult struct {
	URL     string `json:"url"`
	Title   string `json:"title"`
	Snippet string `json:"snippet"`
}

func ddgBase() string {
	if b := os.Getenv("DDG_BASE"); b != "" {
		return b
	}
	return "https://lite.duckduckgo.com/lite/"
}

// searchDDG queries DuckDuckGo Lite and parses the result table.
func searchDDG(q string, max int) []SearchResult {
	if max <= 0 {
		max = 5
	}
	u := ddgBase() + "?q=" + url.QueryEscape(q)
	client := &http.Client{Timeout: 20 * time.Second}
	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return nil
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36")
	req.Header.Set("Accept-Language", "de,en;q=0.9")
	resp, err := client.Do(req)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil
	}
	html := string(body)
	var out []SearchResult
	pos := 0
	for len(out) < max {
		idx := strings.Index(html[pos:], "uddg=")
		if idx < 0 {
			break
		}
		pos += idx
		after := html[pos+len("uddg="):]
		end := strings.IndexAny(after, "&\"'")
		if end < 0 {
			break
		}
		enc := after[:end]
		target, err := url.QueryUnescape(enc)
		if err != nil || !strings.HasPrefix(target, "http") {
			pos += len(enc) + 5
			continue
		}
		title := ""
		if g := strings.Index(after, ">"); g >= 0 {
			if l := strings.Index(after[g:], "</a>"); l >= 0 {
				title = stripTags(after[g+1 : g+l])
			}
		}
		snippet := ""
		if sp := strings.Index(after, "result-snippet'"); sp >= 0 {
			if sg := strings.Index(after[sp:], ">"); sg >= 0 {
				seg := after[sp+sg+1:]
				if st := strings.Index(seg, "</td>"); st >= 0 {
					snippet = strings.Join(strings.Fields(stripTags(seg[:st])), " ")
				}
			}
		}
		if title != "" {
			out = append(out, SearchResult{URL: target, Title: title, Snippet: snippet})
		}
		pos += len(enc) + 5
	}
	return out
}

// searchAPI calls any JSON search endpoint ({q} placeholder or ?q=) and maps
// the response from the common shapes (Google CSE, Brave, Bing, SearXNG,
// Serper, generic array). SSRF-guarded.
func searchAPI(q string, max int, endpoint, key string, allowPrivate bool) []SearchResult {
	if max <= 0 {
		max = 5
	}
	if q == "" || endpoint == "" {
		return nil
	}
	if !safeURL(endpoint, true, allowPrivate) {
		return nil
	}
	u := endpoint
	if strings.Contains(u, "{q}") {
		u = strings.ReplaceAll(u, "{q}", url.QueryEscape(q))
	} else {
		sep := "?"
		if strings.Contains(u, "?") {
			sep = "&"
		}
		u += sep + "q=" + url.QueryEscape(q)
	}
	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return nil
	}
	req.Header.Set("Accept", "application/json")
	if key != "" {
		req.Header.Set("Authorization", "Bearer "+key)
		req.Header.Set("X-API-Key", key)
	}
	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil
	}
	var data any
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return nil
	}
	var out []SearchResult
	specs := []struct {
		items any
		t, u, s string
	}{
		{obj(data, "items"), "title", "link", "snippet"},                 // Google CSE
		{obj(obj(data, "web"), "results"), "title", "url", "description"}, // Brave
		{obj(obj(data, "webPages"), "value"), "name", "url", "snippet"},   // Bing
		{obj(data, "results"), "title", "url", "content"},                // SearXNG
		{obj(data, "organic"), "title", "link", "snippet"},               // Serper
	}
	arr, _ := data.([]any)
	for _, sp := range specs {
		var items []any
		if a, ok := sp.items.([]any); ok {
			items = a
		} else if arr != nil && sp.items == nil {
			items = arr
		}
		for _, it := range items {
			m, _ := it.(map[string]any)
			if m == nil {
				continue
			}
			u2 := first(m, sp.u, "url", "link")
			t := first(m, sp.t, "title")
			s := first(m, sp.s, "snippet", "description", "content")
			if !strings.HasPrefix(u2, "http") || t == "" {
				continue
			}
			out = append(out, SearchResult{URL: u2, Title: stripTags(t), Snippet: stripTags(s)})
			if len(out) >= max {
				break
			}
		}
		if len(out) > 0 {
			break
		}
	}
	if len(out) > max {
		out = out[:max]
	}
	return out
}

func obj(m any, key string) any {
	if mm, ok := m.(map[string]any); ok {
		return mm[key]
	}
	return nil
}

func first(m map[string]any, keys ...string) string {
	for _, k := range keys {
		if v, ok := m[k].(string); ok && v != "" {
			return v
		}
	}
	return ""
}

var tagRe = regexp.MustCompile(`<[^>]+>`)

func stripTags(s string) string {
	s = tagRe.ReplaceAllString(s, "")
	for old, nw := range map[string]string{
		"&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
	} {
		s = strings.ReplaceAll(s, old, nw)
	}
	return strings.TrimSpace(s)
}

func encodeJSON(v any) []byte {
	b, _ := json.Marshal(v)
	return b
}

// small helper to build a POST body (used by provider.go)
func postJSON(client *http.Client, u string, body any, hdr map[string]string, timeout time.Duration) ([]byte, int, error) {
	if timeout == 0 {
		timeout = 120 * time.Second
	}
	client.Timeout = timeout
	var buf bytes.Buffer
	if err := json.NewEncoder(&buf).Encode(body); err != nil {
		return nil, 0, err
	}
	req, err := http.NewRequest("POST", u, &buf)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(resp.Body)
	return b, resp.StatusCode, err
}
