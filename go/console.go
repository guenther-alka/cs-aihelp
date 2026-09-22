package main

// console.go -- interactive cs-console relay for the System > Console menu
// (and later the AI Helpdesk console mode). Transport: SSE out + POST in
// (the same pattern the AI chat already uses for /ask streaming), so no
// WebSocket dependency is needed. The daemon holds the one-time session
// token/key (never shipped to the browser), speaks cs-console's sealed
// ChaCha20-Poly1305 protocol (crypto.go framing in the cs-console repo),
// relays the password-gate conversation (gateMessage JSON) and then the
// raw PTY bytes. See data/howto.ai/cs-console.info, SECURITY -- PASSWORD
// GATE + design D.
//
// Session lifecycle (spawn-per-request, cs-console.info design B):
//   1. the web-GUI Perl CGI calls server.pl's get_tty on the selected
//      member and receives {port, session_token, session_key} (the CGI is
//      the only component that speaks the server.pl protocol).
//   2. the CGI POSTs /console/open {member_ip, port, token, key}; this
//      endpoint dials cs-console and does the one sealed token frame.
//   3. the browser opens GET /console/stream?sid=... (SSE); the pump
//      goroutine starts, running the password gate and then the PTY relay.
//   4. the browser sends input via POST /console/input {sid, data} --
//      during the gate a pending "prompt" consumes it as the password
//      response; after gate "ok" it is written to the PTY as raw bytes.
//
// Window resize is NOT yet supported over the wire (cs-console's relay
// protocol has no resize control frame yet -- follow-up milestone); the
// terminal starts at 80x24 until then.

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/chacha20poly1305"
)

// ---------------------------------------------------------------------------
// sealed framing -- mirrors cs-console's crypto.go exactly
// ---------------------------------------------------------------------------

type sealedWriter struct {
	w    io.Writer
	aead interface {
		Seal(dst, nonce, plaintext, additionalData []byte) []byte
		NonceSize() int
	}
}

func newSealedWriter(w io.Writer, key []byte) (*sealedWriter, error) {
	aead, err := chacha20poly1305.New(key)
	if err != nil {
		return nil, err
	}
	return &sealedWriter{w: w, aead: aead}, nil
}

func (s *sealedWriter) WriteFrame(plaintext []byte) error {
	nonce := make([]byte, s.aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return err
	}
	sealed := s.aead.Seal(nil, nonce, plaintext, nil)
	frame := make([]byte, 4+len(nonce)+len(sealed))
	binary.BigEndian.PutUint32(frame[0:4], uint32(len(nonce)+len(sealed)))
	copy(frame[4:], nonce)
	copy(frame[4+len(nonce):], sealed)
	_, err := s.w.Write(frame)
	return err
}

type sealedReader struct {
	r    io.Reader
	aead interface {
		Open(dst, nonce, ciphertext, additionalData []byte) ([]byte, error)
		NonceSize() int
	}
}

func newSealedReader(r io.Reader, key []byte) (*sealedReader, error) {
	aead, err := chacha20poly1305.New(key)
	if err != nil {
		return nil, err
	}
	return &sealedReader{r: r, aead: aead}, nil
}

const maxFrameLen = 1 << 20

func (s *sealedReader) ReadFrame() ([]byte, error) {
	var lenBuf [4]byte
	if _, err := io.ReadFull(s.r, lenBuf[:]); err != nil {
		return nil, err
	}
	n := binary.BigEndian.Uint32(lenBuf[:])
	if n > maxFrameLen || int(n) < s.aead.NonceSize() {
		return nil, errors.New("cs-console: frame length out of bounds")
	}
	buf := make([]byte, n)
	if _, err := io.ReadFull(s.r, buf); err != nil {
		return nil, err
	}
	nonce := buf[:s.aead.NonceSize()]
	ct := buf[s.aead.NonceSize():]
	return s.aead.Open(nil, nonce, ct, nil)
}

// gateMessage -- mirrors cs-console's auth.go gateMessage wire message.
type gateMessage struct {
	Type string `json:"type"`
	Echo bool   `json:"echo"`
	Text string `json:"text"`
}

// consoleEvent is one unit the pump publishes for the SSE subscriber / poller.
type consoleEvent struct {
	Seq  int
	Kind string // "gate" | "out" | "end"
	Data []byte // gateMessage JSON or raw PTY bytes
	Err  string
}

// consoleSession is one open cs-console relay (one per browser terminal).
type consoleSession struct {
	id   string
	mu   sync.Mutex // serializes conn writes + state transitions
	conn net.Conn
	w    *sealedWriter
	r    *sealedReader

	pwReq  bool // gate: a prompt waits for a password (POST input routes to pwCh)
	pwCh   chan []byte
	subCh  chan consoleEvent // SSE subscriber (legacy/optional)
	relay  bool              // gate passed; frames are raw PTY bytes
	closed bool
	stream bool // an SSE subscriber is attached

	// cs_26.09.06 (AI Helpdesk console mode, Phase 1/2): member-scoped
	// sessions. A human System > Console session is ai=false; an AI Helpdesk
	// console (opened by the password popup) is ai=true and registered per
	// member so /console/ai-status and /console/exec can find it.
	member string
	ai     bool

	// cs_26.09.22: the member's platform (mswin/darwin/freebsd/solaris/
	// illumos/linux, from server.pl _get_tty via cs-console.pl's
	// /console/open body), needed to pick execCommand()'s PTY line-ending.
	// A Windows ConPTY session only submits a line on \r ("\r\n"); a bare
	// "\n" never registers (CONFIRMED, see cs-console.info's own ConPTY
	// finding for the same class of bug in cs-console's password-gate
	// automation -- this is the same issue, just never ported to this,
	// separate, daemon-side exec path). Everything else keeps the
	// original bare "\n", matching cs-console.info's own platform split.
	windows bool

	// cs_26.09.05: poll buffer. The web-GUI's Perl webserver buffers CGI
	// output until the CGI exits, so SSE over a CGI can never stream live.
	// The pump therefore runs from /console/open and buffers every event
	// here with a monotonic Seq; the browser polls /console/poll?since=N.
	evMu    sync.Mutex
	events  []consoleEvent
	lastSeq int

	// cs_26.09.06 (Phase 2): exec collector. While a /console/exec awaits the
	// output of one command, relay "out" frames are routed here instead of the
	// poll buffer; execSent is the sentinel line that marks command completion.
	execMu   sync.Mutex
	execCh   chan []byte
	execSent string
}

var (
	consoleMu       sync.Mutex
	consoleSessions = map[string]*consoleSession{}
)

// newConsoleSession dials cs-console and does the sealed session-token
// frame (the one-time, IP-pinned auth from cs-console design C/D). The
// gate/relay pump is started by handleConsoleOpen (cs_26.09.05: it runs
// from open so events are buffered for /console/poll -- the web-GUI cannot
// stream SSE through its Perl CGI/webserver).
func newConsoleSession(memberIP string, port int, tokenHex, keyHex string, member string, ai bool, windows bool) (*consoleSession, error) {
	key, err := hex.DecodeString(keyHex)
	if err != nil || len(key) != chacha20poly1305.KeySize {
		return nil, errors.New("bad session key")
	}
	token, err := hex.DecodeString(tokenHex)
	if err != nil || len(token) == 0 {
		return nil, errors.New("bad session token")
	}
	addr := net.JoinHostPort(memberIP, strconv.Itoa(port))
	conn, err := net.DialTimeout("tcp", addr, 10*time.Second)
	if err != nil {
		return nil, fmt.Errorf("dialing cs-console %s: %w", addr, err)
	}
	w, err := newSealedWriter(conn, key)
	if err != nil {
		conn.Close()
		return nil, err
	}
	r, err := newSealedReader(conn, key)
	if err != nil {
		conn.Close()
		return nil, err
	}
	if err := w.WriteFrame(token); err != nil {
		conn.Close()
		return nil, fmt.Errorf("sending session token: %w", err)
	}
	s := &consoleSession{
		id:      fmt.Sprintf("c%x", time.Now().UnixNano()),
		member:  member,
		ai:      ai,
		windows: windows,
		conn:    conn,
		w:       w,
		r:       r,
		pwCh:    make(chan []byte, 4),
		subCh:   make(chan consoleEvent, 4096),
	}
	return s, nil
}

// send buffers one event for polling and (best-effort) forwards it to any
// attached SSE subscriber. PTY output ("out") is droppable when nobody is
// reading; gate/end events carry protocol state and must never be lost.
func (s *consoleSession) send(ev consoleEvent) {
	s.evMu.Lock()
	s.lastSeq++
	ev.Seq = s.lastSeq
	if len(s.events) >= 16384 {
		s.events = append([]consoleEvent(nil), s.events[8192:]...)
	}
	s.events = append(s.events, ev)
	s.evMu.Unlock()

	select {
	case s.subCh <- ev:
	default:
		if ev.Kind != "out" {
			go func() {
				select {
				case s.subCh <- ev:
				case <-time.After(2 * time.Second):
				}
			}()
		}
	}
}

func (s *consoleSession) close() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return
	}
	s.closed = true
	s.conn.Close()
	consoleMu.Lock()
	delete(consoleSessions, s.id)
	consoleMu.Unlock()
}

// pump reads cs-console frames and publishes them. It runs the password
// gate conversation first (prompt -> wait for POST input -> forward) and
// then switches to raw PTY output relaying. This is the single reader
// goroutine for the whole session (cs-console's framing is strictly
// sequential, one direction at a time per frame).
func (s *consoleSession) pump() {
	for {
		frame, err := s.r.ReadFrame()
		if err != nil {
			s.send(consoleEvent{Kind: "end", Err: err.Error()})
			s.close()
			return
		}
		if s.relay {
			if s.execCollect(frame) {
				continue
			}
			s.send(consoleEvent{Kind: "out", Data: frame})
			continue
		}
		// gate phase: cs-console sends gateMessage JSON one frame at a time
		var m gateMessage
		if json.Unmarshal(frame, &m) != nil || m.Type == "" {
			s.send(consoleEvent{Kind: "end", Err: "unexpected frame during gate"})
			s.close()
			return
		}
		switch m.Type {
		case "ok":
			s.mu.Lock()
			s.relay = true
			s.mu.Unlock()
			s.send(consoleEvent{Kind: "gate", Data: frame})
		case "prompt":
			s.send(consoleEvent{Kind: "gate", Data: frame})
			s.mu.Lock()
			s.pwReq = true
			s.mu.Unlock()
			select {
			case pw := <-s.pwCh:
				if err := s.w.WriteFrame(pw); err != nil {
					s.send(consoleEvent{Kind: "end", Err: err.Error()})
					s.close()
					return
				}
			case <-time.After(5 * time.Minute):
				s.send(consoleEvent{Kind: "end", Err: "password prompt timed out"})
				s.close()
				return
			}
			s.mu.Lock()
			s.pwReq = false
			s.mu.Unlock()
		default: // info / locked / denied -- pass through; locked/denied are terminal
			s.send(consoleEvent{Kind: "gate", Data: frame})
			if m.Type == "locked" || m.Type == "denied" {
				s.close()
				return
			}
		}
	}
}

// input routes one browser POST to the session. During a pending gate
// prompt it is the password response; after the gate it is raw PTY input.
func (s *consoleSession) input(data []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return errors.New("session closed")
	}
	if !s.relay {
		if s.pwReq {
			select {
			case s.pwCh <- data:
				return nil
			default:
				return errors.New("no pending password prompt")
			}
		}
		return errors.New("console session still in gate phase")
	}
	return s.w.WriteFrame(data)
}

// execCollect routes one relay "out" frame to the active exec collector.
// Returns true if the frame was consumed by a collector (so the caller skips
// the normal poll-buffer send). cs_26.09.06 (Phase 2).
func (s *consoleSession) execCollect(frame []byte) bool {
	s.execMu.Lock()
	defer s.execMu.Unlock()
	if s.execCh == nil {
		return false
	}
	select {
	case s.execCh <- frame:
	default:
		// collector buffer full: drop this bulk-output frame (the sentinel is
		// always short and never dropped). Still count it as consumed so the
		// poll buffer isn't spammed while a command is running.
	}
	return true
}

// findAIConsoleSession returns the live, gate-passed AI console session for a
// member, or nil. Collects candidates under consoleMu, then checks relay/closed
// under each session's own mu (never both at once, to avoid the lock-ordering
// inversion with close()). cs_26.09.06 (Phase 1).
func findAIConsoleSession(member string) *consoleSession {
	consoleMu.Lock()
	var candidates []*consoleSession
	for _, cs := range consoleSessions {
		if cs.ai && cs.member == member {
			candidates = append(candidates, cs)
		}
	}
	consoleMu.Unlock()
	for _, cs := range candidates {
		cs.mu.Lock()
		ok := cs.relay && !cs.closed
		cs.mu.Unlock()
		if ok {
			return cs
		}
	}
	return nil
}

// lineEnding returns the byte sequence that actually submits a line to
// this session's PTY. cs_26.09.22: a Windows ConPTY session is a real
// VT100-style terminal where Enter is CR -- a bare "\n" was CONFIRMED
// (cs-console.info, ConPTY line-ending finding) to never register as a
// submitted line; the input just sits in the shell's line buffer forever.
// That is the actual root cause behind the AI's repeatedly reported
// "Get-Diskecho"-style mangling and empty command output: execCommand()'s
// first WriteFrame(cmd+"\n") never submits on Windows, so the very next
// WriteFrame (the "echo "+marker sentinel) lands appended to the same
// still-open input line instead of running as its own command, and
// NEITHER line ever executes. Mirrors cs-console's own lineEnding() split
// (used for its internal password-gate automation) rather than switching
// unconditionally, to leave already-verified POSIX behavior untouched.
func (s *consoleSession) lineEnding() string {
	if s.windows {
		return "\r\n"
	}
	return "\n"
}

// execCommand runs one command in the member's live shell (Phase 2): writes
// cmd + a unique sentinel echo line into the PTY and collects output until the
// sentinel line appears (or the timeout hits). The sentinel "echo <marker>"
// works identically in POSIX sh/bash and Windows cmd.exe (echo is an alias in
// PowerShell too), so no shell-type detection is needed -- but see
// lineEnding() for the line-ENDING (as opposed to shell-type) split this
// still needs. cs_26.09.06, line-ending fix cs_26.09.22.
func (s *consoleSession) execCommand(cmd string, timeout time.Duration) (string, error) {
	marker := fmt.Sprintf("__CS_EOM_%x__", time.Now().UnixNano()&0xffffff)

	s.execMu.Lock()
	if s.execCh != nil {
		s.execMu.Unlock()
		return "", errors.New("another command is already running in the console")
	}
	ch := make(chan []byte, 4096)
	s.execCh = ch
	s.execSent = marker
	s.execMu.Unlock()

	defer func() {
		s.execMu.Lock()
		s.execCh = nil
		s.execSent = ""
		s.execMu.Unlock()
	}()

	le := s.lineEnding()
	s.mu.Lock()
	err := s.w.WriteFrame([]byte(cmd + le))
	if err == nil {
		err = s.w.WriteFrame([]byte("echo " + marker + le))
	}
	s.mu.Unlock()
	if err != nil {
		return "", fmt.Errorf("writing to console: %w", err)
	}

	var buf []byte
	deadline := time.After(timeout)
	for {
		select {
		case f := <-ch:
			buf = append(buf, f...)
			if bytes.Contains(buf, []byte(marker)) {
				return stripExecOutput(buf, marker), nil
			}
			if len(buf) > 1<<20 {
				return stripExecOutput(buf, marker) + "\n[console: output truncated]", nil
			}
		case <-deadline:
			return stripExecOutput(buf, marker) + "\n[console: command timed out after " + timeout.String() + "]", nil
		}
	}
}

// stripExecOutput cuts the collected PTY stream at the first sentinel
// occurrence (which is the shell's echoed "echo <marker>" line, appearing
// before the marker's own output) and trims trailing newlines. cs_26.09.06.
func stripExecOutput(buf []byte, marker string) string {
	if idx := bytes.Index(buf, []byte(marker)); idx >= 0 {
		buf = buf[:idx]
	}
	return strings.TrimRight(string(buf), "\r\n")
}

// ---------------------------------------------------------------------------
// HTTP handlers (registered in server.go handler())
// ---------------------------------------------------------------------------

func (s *server) handleConsoleOpen(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		MemberIP string `json:"member_ip"`
		Port     int    `json:"port"`
		Token    string `json:"token"`
		Key      string `json:"key"`
		Member   string `json:"member"`   // optional: member name (AI console mode)
		AI       bool   `json:"ai"`       // true = AI Helpdesk console session
		Platform string `json:"platform"` // cs_26.09.22: mswin/darwin/freebsd/solaris/illumos/linux, from server.pl _get_tty (see lineEnding())
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error": "invalid JSON"})
		return
	}
	if req.MemberIP == "" || req.Port <= 0 || req.Port > 65535 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error": "member_ip/port required"})
		return
	}
	cs, err := newConsoleSession(req.MemberIP, req.Port, req.Token, req.Key, req.Member, req.AI, req.Platform == "mswin")
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	consoleMu.Lock()
	consoleSessions[cs.id] = cs
	consoleMu.Unlock()
	// Start the pump immediately (cs_26.09.05): events are buffered in the
	// session for /console/poll. The gate conversation (banner -> password
	// prompt) begins right away instead of waiting for an SSE subscriber.
	go cs.pump()
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "sid": cs.id})
}

// handleConsoleAIStatus reports whether the member has a live, gate-passed AI
// console session. cs_26.09.06 (Phase 1): the Helpdesk polls this before every
// question to decide whether to re-prompt for the root/admin password.
func (s *server) handleConsoleAIStatus(w http.ResponseWriter, r *http.Request) {
	member := r.URL.Query().Get("member")
	if member == "" {
		writeJSON(w, http.StatusOK, map[string]any{"ok": false, "error": "member required"})
		return
	}
	cs := findAIConsoleSession(member)
	if cs == nil {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "active": false})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "active": true, "sid": cs.id})
}

// handleConsoleExec runs one AI command in the member's live console shell
// (Phase 2). Requires an active (gate-passed) AI console session for the
// member, which is what enforces the root/admin password gate in console mode.
func (s *server) handleConsoleExec(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		Member string `json:"member"`
		Cmd    string `json:"cmd"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error": "invalid JSON"})
		return
	}
	if req.Cmd == "" {
		writeJSON(w, http.StatusOK, map[string]any{"ok": false, "error": "no command"})
		return
	}
	cs := findAIConsoleSession(req.Member)
	if cs == nil {
		writeJSON(w, http.StatusOK, map[string]any{"ok": false, "error": "no active console session -- unlock the console first (root/admin password)"})
		return
	}
	output, err := cs.execCommand(req.Cmd, 60*time.Second)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "output": output})
}

// handleConsolePoll returns all buffered events with Seq > since as JSON.
// The System > Console page polls this every ~300ms (the Perl webserver
// cannot stream CGI output, so SSE over a CGI is unusable there).
func (s *server) handleConsolePoll(w http.ResponseWriter, r *http.Request) {
	sid := r.URL.Query().Get("sid")
	since := 0
	if v := r.URL.Query().Get("since"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			since = n
		}
	}
	cs := consoleSessions[sid]
	if cs == nil {
		writeJSON(w, http.StatusOK, map[string]any{"ok": false, "error": "no such session"})
		return
	}
	cs.evMu.Lock()
	evs := make([]map[string]any, 0, 8)
	last := since
	for _, ev := range cs.events {
		if ev.Seq <= since {
			continue
		}
		last = ev.Seq
		e := map[string]any{"i": ev.Seq, "kind": ev.Kind}
		if ev.Kind == "out" {
			e["data"] = base64.StdEncoding.EncodeToString(ev.Data)
		} else {
			// gate/end events are small utf8 JSON/text
			e["data"] = string(ev.Data)
		}
		if ev.Err != "" {
			e["err"] = ev.Err
		}
		evs = append(evs, e)
	}
	closed := cs.closed
	cs.evMu.Unlock()
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "seq": last, "events": evs, "closed": closed})
}

func (s *server) handleConsoleInput(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		SID  string `json:"sid"`
		Data string `json:"data"` // base64
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error": "invalid JSON"})
		return
	}
	raw, err := base64.StdEncoding.DecodeString(req.Data)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error": "data must be base64"})
		return
	}
	cs := consoleSessions[req.SID]
	if cs == nil {
		writeJSON(w, http.StatusOK, map[string]any{"ok": false, "error": "no such session"})
		return
	}
	if err := cs.input(raw); err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *server) handleConsoleClose(w http.ResponseWriter, r *http.Request) {
	var req struct {
		SID string `json:"sid"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error": "invalid JSON"})
		return
	}
	if cs := consoleSessions[req.SID]; cs != nil {
		cs.close()
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

// handleConsoleStream is the legacy SSE endpoint (kept for direct/CLI use;
// the web-GUI uses /console/poll because its Perl webserver cannot stream
// CGI output). The session pump already runs from /console/open, so this
// only attaches a subscriber. One subscriber per session.
func (s *server) handleConsoleStream(w http.ResponseWriter, r *http.Request) {
	sid := r.URL.Query().Get("sid")
	cs := consoleSessions[sid]
	if cs == nil {
		http.Error(w, "no such session", http.StatusNotFound)
		return
	}
	cs.mu.Lock()
	if cs.stream || cs.closed {
		cs.mu.Unlock()
		http.Error(w, "session already has a stream", http.StatusConflict)
		return
	}
	cs.stream = true
	cs.mu.Unlock()
	fl, _ := w.(http.Flusher)
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(http.StatusOK)
	if fl != nil {
		fl.Flush()
	}
	keepAlive := time.NewTicker(15 * time.Second)
	defer keepAlive.Stop()
	for {
		select {
		case ev := <-cs.subCh:
			switch ev.Kind {
			case "gate":
				fmt.Fprintf(w, "event: gate\ndata: %s\n\n", ev.Data)
			case "out":
				fmt.Fprintf(w, "event: out\ndata: %s\n\n",
					base64.StdEncoding.EncodeToString(ev.Data))
			default: // end
				msg, _ := json.Marshal(map[string]string{"error": ev.Err})
				fmt.Fprintf(w, "event: end\ndata: %s\n\n", msg)
				if fl != nil {
					fl.Flush()
				}
				cs.close()
				return
			}
			if fl != nil {
				fl.Flush()
			}
		case <-keepAlive.C:
			fmt.Fprint(w, ": keep-alive\n\n")
			if fl != nil {
				fl.Flush()
			}
		case <-r.Context().Done():
			cs.close()
			return
		}
	}
}
