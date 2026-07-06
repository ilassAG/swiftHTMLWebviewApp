package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/nats-io/nats.go"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}

func run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		usage(stderr)
		return 2
	}
	switch args[0] {
	case "watch":
		if err := runWatch(args[1:], stdout, stderr); err != nil {
			fmt.Fprintln(stderr, "watch:", err)
			return 1
		}
	case "start":
		if err := runStart(args[1:], stdout, stderr); err != nil {
			fmt.Fprintln(stderr, "start:", err)
			return 1
		}
	case "stop":
		if err := runStop(args[1:], stdout, stderr); err != nil {
			fmt.Fprintln(stderr, "stop:", err)
			return 1
		}
	case "qr":
		if err := runQR(args[1:], stdout, stderr); err != nil {
			fmt.Fprintln(stderr, "qr:", err)
			return 1
		}
	case "command":
		if err := runCommand(args[1:], stdin, stdout, stderr); err != nil {
			fmt.Fprintln(stderr, "command:", err)
			return 1
		}
	case "help", "-h", "--help":
		usage(stdout)
	default:
		fmt.Fprintf(stderr, "unknown command %q\n\n", args[0])
		usage(stderr)
		return 2
	}
	return 0
}

func usage(w io.Writer) {
	fmt.Fprintln(w, `Usage:
  natscontrol watch   -app APP-UUID [flags]
  natscontrol start   -app APP-UUID [flags]
  natscontrol stop    -app APP-UUID [flags]
  natscontrol qr      -app APP-UUID -image qr.png [flags]
  natscontrol command -app APP-UUID -action settingsGet -json '{}' [flags]

Common flags use NATS_URL, NATS_CREDS, NATS_TOKEN, NATS_USER, NATS_PASSWORD,
NATS_APP_UUID, and NATS_SUBJECT_PREFIX when present. Use -creds for .creds
files; do not put credential material in command JSON.`)
}

func runWatch(args []string, stdout, stderr io.Writer) error {
	cfg := defaultCommonConfig()
	fs := flag.NewFlagSet("watch", flag.ContinueOnError)
	fs.SetOutput(stderr)
	addCommonFlags(fs, &cfg)
	httpAddr := fs.String("http", ":18091", "HTTP viewer listen address; empty disables HTTP")
	frameSubject := fs.String("frames-subject", "", "override frame subject")
	metaSubject := fs.String("meta-subject", "", "override metadata subject")
	eventSubject := fs.String("event-subject", "", "override stream event subject")
	responseSubject := fs.String("response-subject", "", "override command response subject")
	statusSubject := fs.String("status-subject", "", "override status subject")
	telemetrySubject := fs.String("telemetry-subject", "", "override telemetry subject")
	quiet := fs.Bool("quiet", false, "do not print meta/events/replies to stdout")
	if err := fs.Parse(args); err != nil {
		return err
	}
	subjects, err := cfg.subjects()
	if err != nil {
		return err
	}
	if *frameSubject != "" {
		subjects.Frames = strings.TrimSpace(*frameSubject)
	}
	if *metaSubject != "" {
		subjects.Meta = strings.TrimSpace(*metaSubject)
	}
	if *eventSubject != "" {
		subjects.Events = strings.TrimSpace(*eventSubject)
	}
	if *responseSubject != "" {
		subjects.Responses = strings.TrimSpace(*responseSubject)
	}
	if *statusSubject != "" {
		subjects.Status = strings.TrimSpace(*statusSubject)
	}
	if *telemetrySubject != "" {
		subjects.Telemetry = strings.TrimSpace(*telemetrySubject)
	}

	nc, err := cfg.connect()
	if err != nil {
		return err
	}
	defer nc.Drain()

	state := newStreamState(subjects)
	if _, err := nc.Subscribe(subjects.Frames, func(msg *nats.Msg) {
		state.recordFrame(msg.Subject, msg.Data)
	}); err != nil {
		return err
	}
	for _, spec := range []struct {
		kind    string
		subject string
	}{
		{"meta", subjects.Meta},
		{"event", subjects.Events},
		{"reply", subjects.Responses},
		{"status", subjects.Status},
		{"telemetry", subjects.Telemetry},
	} {
		kind := spec.kind
		subject := spec.subject
		if subject == "" {
			continue
		}
		if _, err := nc.Subscribe(subject, func(msg *nats.Msg) {
			state.recordText(kind, msg.Data)
			if !*quiet {
				fmt.Fprintf(stdout, "[%s] %s %s\n%s\n", time.Now().Format(time.RFC3339), kind, msg.Subject, formatMaybeJSON(msg.Data))
			}
		}); err != nil {
			return err
		}
	}
	if err := nc.Flush(); err != nil {
		return err
	}

	var server *http.Server
	if strings.TrimSpace(*httpAddr) != "" {
		ln, err := net.Listen("tcp", strings.TrimSpace(*httpAddr))
		if err != nil {
			return fmt.Errorf("cannot listen on %s: %w", *httpAddr, err)
		}
		server = &http.Server{Handler: viewerHandler(state)}
		go func() {
			if err := server.Serve(ln); err != nil && err != http.ErrServerClosed {
				fmt.Fprintln(stderr, "http viewer:", err)
			}
		}()
		fmt.Fprintf(stdout, "NATS viewer listening on %s\n", localHTTPURL(ln.Addr().String()))
	}

	fmt.Fprintf(stdout, "subscribed: frames=%s meta=%s events=%s replies=%s status=%s telemetry=%s\n",
		subjects.Frames, subjects.Meta, subjects.Events, subjects.Responses, subjects.Status, subjects.Telemetry)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	<-ctx.Done()
	if server != nil {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}
	return nil
}

func runStart(args []string, stdout, stderr io.Writer) error {
	cfg := defaultCommonConfig()
	fs := flag.NewFlagSet("start", flag.ContinueOnError)
	fs.SetOutput(stderr)
	addCommonFlags(fs, &cfg)
	requestIDFlag := fs.String("request-id", "", "requestId to send")
	frameSubject := fs.String("frames-subject", "", "frame subject override")
	metaSubject := fs.String("meta-subject", "", "metadata subject override")
	eventSubject := fs.String("event-subject", "", "stream event subject override")
	fps := fs.Int("fps", 2, "stream frames per second, clamped by app")
	quality := fs.Int("quality", 65, "JPEG quality percent, clamped by app")
	maxWidth := fs.Int("max-width", 720, "max frame width, clamped by app")
	format := fs.String("format", "jpeg", "stream format")
	source := fs.String("source", "app", "capture source: app is implemented; device is reserved")
	noWait := fs.Bool("no-wait", false, "publish without waiting for a reply")
	if err := fs.Parse(args); err != nil {
		return err
	}
	subjects, err := cfg.subjects()
	if err != nil {
		return err
	}
	payload := buildScreenStreamStart(subjects, streamStartOptions{
		RequestID:    *requestIDFlag,
		FrameSubject: *frameSubject,
		MetaSubject:  *metaSubject,
		EventSubject: *eventSubject,
		FPS:          *fps,
		Quality:      *quality,
		MaxWidth:     *maxWidth,
		Format:       *format,
		Source:       *source,
	})
	return publishCommand(cfg, commandSubject(subjects, "screenStreamStart"), payload, !*noWait, stdout)
}

func runStop(args []string, stdout, stderr io.Writer) error {
	cfg := defaultCommonConfig()
	fs := flag.NewFlagSet("stop", flag.ContinueOnError)
	fs.SetOutput(stderr)
	addCommonFlags(fs, &cfg)
	requestIDFlag := fs.String("request-id", "", "requestId to send")
	noWait := fs.Bool("no-wait", false, "publish without waiting for a reply")
	if err := fs.Parse(args); err != nil {
		return err
	}
	subjects, err := cfg.subjects()
	if err != nil {
		return err
	}
	return publishCommand(cfg, commandSubject(subjects, "screenStreamStop"), buildScreenStreamStop(*requestIDFlag), !*noWait, stdout)
}

func runQR(args []string, stdout, stderr io.Writer) error {
	cfg := defaultCommonConfig()
	fs := flag.NewFlagSet("qr", flag.ContinueOnError)
	fs.SetOutput(stderr)
	addCommonFlags(fs, &cfg)
	imagePath := fs.String("image", "", "image file to send as dataURL")
	dataURL := fs.String("data-url", "", "prebuilt data:image/... URL")
	requestIDFlag := fs.String("request-id", "", "requestId to send")
	jobID := fs.String("job-id", "", "jobId to echo in the wrapper reply")
	noWait := fs.Bool("no-wait", false, "publish without waiting for a reply")
	if err := fs.Parse(args); err != nil {
		return err
	}
	subjects, err := cfg.subjects()
	if err != nil {
		return err
	}
	payload, err := buildQRScanImage(*imagePath, *dataURL, *requestIDFlag, *jobID)
	if err != nil {
		return err
	}
	return publishCommand(cfg, commandSubject(subjects, "qrScanImage"), payload, !*noWait, stdout)
}

func runCommand(args []string, stdin io.Reader, stdout, stderr io.Writer) error {
	cfg := defaultCommonConfig()
	fs := flag.NewFlagSet("command", flag.ContinueOnError)
	fs.SetOutput(stderr)
	addCommonFlags(fs, &cfg)
	action := fs.String("action", "", "bridge action to send; used as command subject suffix if -subject is empty")
	subject := fs.String("subject", "", "explicit command subject")
	jsonText := fs.String("json", "", "JSON object payload")
	jsonPath := fs.String("json-file", "", "path to JSON object payload")
	readStdin := fs.Bool("stdin", false, "read JSON object payload from stdin")
	noWait := fs.Bool("no-wait", false, "publish without waiting for a reply")
	if err := fs.Parse(args); err != nil {
		return err
	}
	subjects, err := cfg.subjects()
	if err != nil {
		return err
	}
	payload, err := readJSONObject(*jsonText, *jsonPath, *readStdin, stdin)
	if err != nil {
		return err
	}
	if strings.TrimSpace(*action) != "" {
		payload["action"] = strings.TrimSpace(*action)
	}
	if _, ok := payload["requestId"]; !ok {
		payload["requestId"] = requestID(nonEmptyAction(payload, "natsCommand"))
	}
	commandSubjectValue := strings.TrimSpace(*subject)
	if commandSubjectValue == "" {
		actionValue := nonEmptyAction(payload, "")
		if actionValue == "" {
			return fmt.Errorf("-action is required when -subject is not set")
		}
		commandSubjectValue = commandSubject(subjects, actionValue)
	}
	return publishCommand(cfg, commandSubjectValue, payload, !*noWait, stdout)
}

func publishCommand(cfg commonConfig, subject string, payload map[string]any, waitForReply bool, stdout io.Writer) error {
	data, err := marshalJSONObject(payload)
	if err != nil {
		return err
	}
	nc, err := cfg.connect()
	if err != nil {
		return err
	}
	defer nc.Close()

	if waitForReply {
		reply, err := nc.Request(subject, data, cfg.Timeout)
		if err != nil {
			return err
		}
		return printPayload(stdout, reply.Data)
	}
	if err := nc.Publish(subject, data); err != nil {
		return err
	}
	if err := nc.Flush(); err != nil {
		return err
	}
	fmt.Fprintf(stdout, "published %d bytes to %s\n", len(data), subject)
	return nil
}

func printPayload(w io.Writer, data []byte) error {
	var value any
	if err := json.Unmarshal(data, &value); err == nil {
		pretty, err := json.MarshalIndent(value, "", "  ")
		if err != nil {
			return err
		}
		_, err = fmt.Fprintln(w, string(pretty))
		return err
	}
	_, err := fmt.Fprintln(w, strings.TrimSpace(string(data)))
	return err
}

func nonEmptyAction(payload map[string]any, fallback string) string {
	if value, ok := payload["action"].(string); ok && strings.TrimSpace(value) != "" {
		return strings.TrimSpace(value)
	}
	return fallback
}

func localHTTPURL(addr string) string {
	if strings.HasPrefix(addr, ":") {
		return "http://127.0.0.1" + addr + "/"
	}
	if strings.HasPrefix(addr, "[::]:") {
		return "http://127.0.0.1:" + strings.TrimPrefix(addr, "[::]:") + "/"
	}
	if strings.HasPrefix(addr, "0.0.0.0:") {
		return "http://127.0.0.1:" + strings.TrimPrefix(addr, "0.0.0.0:") + "/"
	}
	return "http://" + addr + "/"
}
