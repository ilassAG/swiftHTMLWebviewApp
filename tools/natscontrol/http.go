package main

import (
	"encoding/json"
	"io"
	"net/http"
)

func viewerHandler(state *streamState) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/", indexHandler)
	mux.HandleFunc("/stats", statsHandler(state))
	mux.HandleFunc("/frame.jpg", frameHandler(state))
	return mux
}

func indexHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	io.WriteString(w, `<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>NATS Screenstream Viewer</title>
  <style>
    html, body { min-height: 100%; }
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #101113; color: #f5f5f5; }
    main { display: grid; grid-template-rows: auto auto minmax(220px, 1fr) auto; gap: 12px; padding: 12px; max-width: 1200px; min-height: 100vh; box-sizing: border-box; margin: 0 auto; }
    h1 { margin: 0; font-size: 24px; }
    .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; }
    .tile { background: #202124; border: 1px solid #383a3f; border-radius: 8px; padding: 12px; }
    .tile strong { display: block; font-size: 12px; color: #aeb4bf; text-transform: uppercase; letter-spacing: .03em; }
    .tile span { display: block; margin-top: 6px; font-size: 24px; font-weight: 700; }
    .frame { height: min(70vh, 760px); min-height: 220px; background: #050505; display: flex; align-items: center; justify-content: center; border: 1px solid #383a3f; border-radius: 8px; overflow: hidden; }
    img { max-width: 100%; max-height: 100%; width: auto; height: auto; object-fit: contain; display: block; }
    .logs { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 10px; }
    pre { max-height: 24vh; overflow: auto; white-space: pre-wrap; word-break: break-word; background: #202124; border: 1px solid #383a3f; border-radius: 8px; padding: 12px; margin: 0; font-size: 12px; }
  </style>
</head>
<body>
  <main>
    <h1>NATS Screenstream Viewer</h1>
    <section class="stats">
      <div class="tile"><strong>Frames</strong><span id="frames">0</span></div>
      <div class="tile"><strong>Daten</strong><span id="bytes">0 B</span></div>
      <div class="tile"><strong>Durchsatz</strong><span id="bps">0 B/s</span></div>
      <div class="tile"><strong>FPS</strong><span id="fps">0</span></div>
      <div class="tile"><strong>Meta</strong><span id="meta">0</span></div>
      <div class="tile"><strong>Events</strong><span id="events">0</span></div>
      <div class="tile"><strong>Replies</strong><span id="replies">0</span></div>
      <div class="tile"><strong>Telemetry</strong><span id="telemetry">0</span></div>
    </section>
    <section class="frame"><img id="frame" alt="Letzter NATS Screenstream Frame"></section>
    <section class="logs">
      <pre id="subjects">{}</pre>
      <pre id="metaRaw">{}</pre>
      <pre id="eventRaw">{}</pre>
      <pre id="replyRaw">{}</pre>
      <pre id="telemetryRaw">{}</pre>
    </section>
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
      document.getElementById("bytes").textContent = fmt(stats.frameBytes);
      document.getElementById("bps").textContent = fmt(stats.bytesPerSecond) + "/s";
      document.getElementById("fps").textContent = Number(stats.fpsAverage || 0).toFixed(2);
      document.getElementById("meta").textContent = stats.metaMessages;
      document.getElementById("events").textContent = stats.eventMessages;
      document.getElementById("replies").textContent = stats.replyMessages;
      document.getElementById("telemetry").textContent = stats.telemetryMessages;
      document.getElementById("subjects").textContent = JSON.stringify(stats.subjects, null, 2);
      document.getElementById("metaRaw").textContent = stats.lastMeta || "{}";
      document.getElementById("eventRaw").textContent = stats.lastEvent || "{}";
      document.getElementById("replyRaw").textContent = stats.lastReply || "{}";
      document.getElementById("telemetryRaw").textContent = stats.lastTelemetry || "{}";
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
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
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
