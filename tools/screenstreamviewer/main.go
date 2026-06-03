package main

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

const wsGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

type streamState struct {
	mu             sync.RWMutex
	startedAt      time.Time
	lastFrameAt    time.Time
	lastFrame      []byte
	lastFrameBytes int
	totalBytes     int64
	totalFrames    int64
	connections    int64
	meta           string
}

func newStreamState() *streamState {
	return &streamState{startedAt: time.Now()}
}

func (s *streamState) recordFrame(frame []byte) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastFrame = append(s.lastFrame[:0], frame...)
	s.lastFrameBytes = len(frame)
	s.totalBytes += int64(len(frame))
	s.totalFrames += 1
	s.lastFrameAt = time.Now()
}

func (s *streamState) recordMeta(meta string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.meta = meta
}

func (s *streamState) addConnection() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.connections += 1
}

func (s *streamState) snapshot() map[string]any {
	s.mu.RLock()
	defer s.mu.RUnlock()
	duration := time.Since(s.startedAt).Seconds()
	if duration <= 0 {
		duration = 0.001
	}
	lastAgeMs := -1
	if !s.lastFrameAt.IsZero() {
		lastAgeMs = int(time.Since(s.lastFrameAt).Milliseconds())
	}
	return map[string]any{
		"startedAt":        s.startedAt.Format(time.RFC3339),
		"connections":      s.connections,
		"frames":           s.totalFrames,
		"bytes":            s.totalBytes,
		"bytesPerSecond":   float64(s.totalBytes) / duration,
		"fpsAverage":       float64(s.totalFrames) / duration,
		"lastFrameBytes":   s.lastFrameBytes,
		"lastFrameAgeMs":   lastAgeMs,
		"hasFrame":         len(s.lastFrame) > 0,
		"lastMetadataJSON": s.meta,
	}
}

func (s *streamState) latestFrame() []byte {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return append([]byte(nil), s.lastFrame...)
}

func main() {
	addr := flag.String("addr", ":18090", "HTTP/WebSocket listen address")
	flag.Parse()

	state := newStreamState()
	mux := http.NewServeMux()
	mux.HandleFunc("/", indexHandler)
	mux.HandleFunc("/stats", statsHandler(state))
	mux.HandleFunc("/frame.jpg", frameHandler(state))
	mux.HandleFunc("/screen", screenWebSocketHandler(state))

	log.Printf("screenstream viewer listening on http://0.0.0.0%s", *addr)
	log.Printf("native target URL: ws://<this-mac-ip>%s/screen", *addr)
	if err := http.ListenAndServe(*addr, mux); err != nil {
		log.Fatal(err)
	}
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	io.WriteString(w, `<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Screenstream Viewer</title>
  <style>
    html, body { min-height: 100%; }
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #111; color: #f5f5f5; }
    main { display: grid; grid-template-rows: auto auto minmax(220px, 1fr) auto; gap: 12px; padding: 12px; max-width: 1100px; min-height: 100vh; box-sizing: border-box; margin: 0 auto; }
    h1 { margin: 0; }
    .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; }
    .tile { background: #202124; border: 1px solid #383a3f; border-radius: 8px; padding: 12px; }
    .tile strong { display: block; font-size: 12px; color: #aeb4bf; text-transform: uppercase; letter-spacing: .03em; }
    .tile span { display: block; margin-top: 6px; font-size: 24px; font-weight: 700; }
    .frame { height: min(72vh, 760px); min-height: 220px; background: #050505; display: flex; align-items: center; justify-content: center; border: 1px solid #383a3f; border-radius: 8px; overflow: hidden; }
    img { max-width: 100%; max-height: 100%; width: auto; height: auto; object-fit: contain; display: block; }
    pre { max-height: 18vh; overflow: auto; white-space: pre-wrap; word-break: break-word; background: #202124; border: 1px solid #383a3f; border-radius: 8px; padding: 12px; margin: 0; }
  </style>
</head>
<body>
  <main>
    <h1>Screenstream Viewer</h1>
    <section class="stats">
      <div class="tile"><strong>Frames</strong><span id="frames">0</span></div>
      <div class="tile"><strong>Daten</strong><span id="bytes">0 B</span></div>
      <div class="tile"><strong>Durchsatz</strong><span id="bps">0 B/s</span></div>
      <div class="tile"><strong>FPS</strong><span id="fps">0</span></div>
      <div class="tile"><strong>Letzter Frame</strong><span id="last">-</span></div>
    </section>
    <section class="frame"><img id="frame" alt="Letzter Screenstream Frame"></section>
    <pre id="raw">{}</pre>
  </main>
  <script>
    function fmt(bytes) {
      if (bytes >= 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(2) + " MB";
      if (bytes >= 1024) return (bytes / 1024).toFixed(1) + " KB";
      return Math.round(bytes) + " B";
    }
    async function tick() {
      const stats = await fetch("/stats", { cache: "no-store" }).then(r => r.json());
      document.getElementById("frames").textContent = stats.frames;
      document.getElementById("bytes").textContent = fmt(stats.bytes);
      document.getElementById("bps").textContent = fmt(stats.bytesPerSecond) + "/s";
      document.getElementById("fps").textContent = Number(stats.fpsAverage || 0).toFixed(2);
      document.getElementById("last").textContent = stats.lastFrameBytes ? fmt(stats.lastFrameBytes) : "-";
      document.getElementById("raw").textContent = JSON.stringify(stats, null, 2);
      if (stats.hasFrame) {
        document.getElementById("frame").src = "/frame.jpg?t=" + Date.now();
      }
    }
    setInterval(tick, 500);
    tick();
  </script>
</body>
</html>`)
}

func statsHandler(state *streamState) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(state.snapshot())
	}
}

func frameHandler(state *streamState) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		frame := state.latestFrame()
		if len(frame) == 0 {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "image/jpeg")
		w.Header().Set("Cache-Control", "no-store")
		w.Write(frame)
	}
}

func screenWebSocketHandler(state *streamState) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
			http.Error(w, "websocket upgrade required", http.StatusBadRequest)
			return
		}
		hijacker, ok := w.(http.Hijacker)
		if !ok {
			http.Error(w, "hijacking not supported", http.StatusInternalServerError)
			return
		}
		conn, rw, err := hijacker.Hijack()
		if err != nil {
			return
		}
		defer conn.Close()

		key := r.Header.Get("Sec-WebSocket-Key")
		if key == "" {
			return
		}
		accept := websocketAccept(key)
		fmt.Fprintf(rw, "HTTP/1.1 101 Switching Protocols\r\n")
		fmt.Fprintf(rw, "Upgrade: websocket\r\n")
		fmt.Fprintf(rw, "Connection: Upgrade\r\n")
		fmt.Fprintf(rw, "Sec-WebSocket-Accept: %s\r\n\r\n", accept)
		rw.Flush()

		state.addConnection()
		reader := bufio.NewReader(conn)
		for {
			opcode, payload, err := readWebSocketFrame(reader)
			if err != nil {
				if !errors.Is(err, io.EOF) {
					log.Printf("websocket read failed: %v", err)
				}
				return
			}
			switch opcode {
			case 1:
				state.recordMeta(string(payload))
			case 2:
				state.recordFrame(payload)
			case 8:
				writeCloseFrame(conn)
				return
			case 9:
				writePongFrame(conn, payload)
			}
		}
	}
}

func websocketAccept(key string) string {
	sum := sha1.Sum([]byte(key + wsGUID))
	return base64.StdEncoding.EncodeToString(sum[:])
}

func readWebSocketFrame(reader *bufio.Reader) (byte, []byte, error) {
	header := make([]byte, 2)
	if _, err := io.ReadFull(reader, header); err != nil {
		return 0, nil, err
	}
	opcode := header[0] & 0x0f
	masked := header[1]&0x80 != 0
	length := uint64(header[1] & 0x7f)
	switch length {
	case 126:
		var ext [2]byte
		if _, err := io.ReadFull(reader, ext[:]); err != nil {
			return 0, nil, err
		}
		length = uint64(binary.BigEndian.Uint16(ext[:]))
	case 127:
		var ext [8]byte
		if _, err := io.ReadFull(reader, ext[:]); err != nil {
			return 0, nil, err
		}
		length = binary.BigEndian.Uint64(ext[:])
	}
	if length > 32*1024*1024 {
		return 0, nil, fmt.Errorf("frame too large: %d bytes", length)
	}
	var mask [4]byte
	if masked {
		if _, err := io.ReadFull(reader, mask[:]); err != nil {
			return 0, nil, err
		}
	}
	payload := make([]byte, length)
	if _, err := io.ReadFull(reader, payload); err != nil {
		return 0, nil, err
	}
	if masked {
		for i := range payload {
			payload[i] ^= mask[i%4]
		}
	}
	return opcode, payload, nil
}

func writeCloseFrame(conn net.Conn) {
	conn.Write([]byte{0x88, 0x00})
}

func writePongFrame(conn net.Conn, payload []byte) {
	if len(payload) > 125 {
		payload = payload[:125]
	}
	frame := append([]byte{0x8a, byte(len(payload))}, payload...)
	conn.Write(frame)
}
