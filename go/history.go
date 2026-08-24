package main

// history.go -- chat history in _cfg/aihelp/conv_<ts>_<rand>.json.
// The JSON layout is identical to the Perl frontend version so existing
// conversations carry over (created, updated, member, title, messages[]).

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"time"
)

type Msg struct {
	Role string `json:"role"`
	Ts   int64  `json:"ts"`
	Text string `json:"text"`
}

type Conversation struct {
	Created  int64  `json:"created"`
	Updated  int64  `json:"updated"`
	Member   string `json:"member"`
	Title    string `json:"title"`
	Messages []Msg  `json:"messages"`
}

type ConvMeta struct {
	ID    string `json:"id"`
	Mtime int64  `json:"mtime"`
	Title string `json:"title"`
}

var convIDRe = regexp.MustCompile(`[^A-Za-z0-9_.-]`)

func historyDir(base string) string {
	dir := filepath.Join(base, "_cfg", "aihelp")
	os.MkdirAll(dir, 0700)
	return dir
}

func sanitizeConvID(id string) string {
	return convIDRe.ReplaceAllString(id, "")
}

func newConvID() string {
	return fmt.Sprintf("%d_%04x%04x", time.Now().UnixNano()/1e9, time.Now().Unix()%0xffff, os.Getpid())
}

func loadConv(base, id string) (*Conversation, error) {
	id = sanitizeConvID(id)
	if id == "" {
		return nil, fmt.Errorf("bad conv id")
	}
	b, err := os.ReadFile(filepath.Join(historyDir(base), "conv_"+id+".json"))
	if err != nil {
		return nil, err
	}
	var c Conversation
	if err := json.Unmarshal(b, &c); err != nil {
		return nil, err
	}
	return &c, nil
}

func saveConv(base, id string, c *Conversation) error {
	id = sanitizeConvID(id)
	if id == "" {
		return fmt.Errorf("bad conv id")
	}
	b, err := json.Marshal(c)
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(historyDir(base), "conv_"+id+".json"), b, 0600)
}

func listConvs(base string) []ConvMeta {
	dir := historyDir(base)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var out []ConvMeta
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if len(name) < 10 || name[:5] != "conv_" || filepath.Ext(name) != ".json" {
			continue
		}
		id := name[5 : len(name)-5]
		fi, _ := e.Info()
		mtime := int64(0)
		if fi != nil {
			mtime = fi.ModTime().Unix()
		}
		title := ""
		if c, err := loadConv(base, id); err == nil {
			title = c.Title
			if title == "" {
				for _, m := range c.Messages {
					if m.Role == "user" {
						t := m.Text
						if len(t) > 60 {
							t = t[:60]
						}
						title = t
						break
					}
				}
			}
		}
		out = append(out, ConvMeta{ID: id, Mtime: mtime, Title: title})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Mtime > out[j].Mtime })
	return out
}

// cleanupConvs deletes conversations older than the retention window.
// retention: off|today|week|month|6months|all (days mapped inside).
func cleanupConvs(base, retention string) {
	days := map[string]int{"today": 1, "week": 7, "month": 30, "6months": 180}[retention]
	if days <= 0 {
		return
	}
	cutoff := time.Now().Add(-time.Duration(days) * 24 * time.Hour).Unix()
	for _, c := range listConvs(base) {
		if c.Mtime < cutoff {
			os.Remove(filepath.Join(historyDir(base), "conv_"+c.ID+".json"))
		}
	}
}
