package main

import (
	"crypto/rand"
	"crypto/tls"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/nats-io/nats.go"
)

const (
	defaultNamespace = "swift.wrapper"
	defaultNATSURL   = "nats://127.0.0.1:4222"
)

type commonConfig struct {
	Servers     string
	CredsPath   string
	Token       string
	User        string
	Password    string
	ClientName  string
	TLS         bool
	TLSInsecure bool
	AppUUID     string
	Prefix      string
	Namespace   string
	Timeout     time.Duration
}

type subjectSet struct {
	Prefix      string
	Frames      string
	Meta        string
	Events      string
	Responses   string
	Status      string
	Telemetry   string
	CommandRoot string
}

func defaultCommonConfig() commonConfig {
	hostname, _ := os.Hostname()
	if hostname == "" {
		hostname = "localhost"
	}
	return commonConfig{
		Servers:    firstEnv("NATS_URL", "NATS_SERVERS", defaultNATSURL),
		CredsPath:  firstEnv("NATS_CREDS", "NATS_CREDS_PATH", ""),
		Token:      firstEnv("NATS_TOKEN", ""),
		User:       firstEnv("NATS_USER", "NATS_USERNAME", ""),
		Password:   firstEnv("NATS_PASSWORD", "NATS_PASS", ""),
		ClientName: firstEnv("NATS_CLIENT_NAME", "swift-wrapper-natscontrol-"+hostname),
		AppUUID:    firstEnv("NATS_APP_UUID", "SWIFT_WRAPPER_APP_UUID", ""),
		Prefix:     firstEnv("NATS_SUBJECT_PREFIX", "SWIFT_WRAPPER_NATS_PREFIX", ""),
		Namespace:  firstEnv("NATS_NAMESPACE", defaultNamespace),
		Timeout:    8 * time.Second,
	}
}

func addCommonFlags(fs *flag.FlagSet, cfg *commonConfig) {
	fs.StringVar(&cfg.Servers, "server", cfg.Servers, "NATS server URL(s), comma-separated; env NATS_URL or NATS_SERVERS")
	fs.StringVar(&cfg.Servers, "servers", cfg.Servers, "alias for -server")
	fs.StringVar(&cfg.CredsPath, "creds", cfg.CredsPath, "path to NATS .creds file; env NATS_CREDS")
	fs.StringVar(&cfg.Token, "token", cfg.Token, "NATS token; env NATS_TOKEN")
	fs.StringVar(&cfg.User, "user", cfg.User, "NATS username; env NATS_USER")
	fs.StringVar(&cfg.Password, "password", cfg.Password, "NATS password; env NATS_PASSWORD")
	fs.StringVar(&cfg.ClientName, "name", cfg.ClientName, "NATS client name; env NATS_CLIENT_NAME")
	fs.BoolVar(&cfg.TLS, "tls", envBool("NATS_TLS", false), "force TLS for nats:// URLs; env NATS_TLS")
	fs.BoolVar(&cfg.TLSInsecure, "tls-insecure", envBool("NATS_TLS_INSECURE", false), "skip TLS certificate verification for local testing only; env NATS_TLS_INSECURE")
	fs.StringVar(&cfg.AppUUID, "app", cfg.AppUUID, "wrapper appUUID; env NATS_APP_UUID")
	fs.StringVar(&cfg.Prefix, "prefix", cfg.Prefix, "device subject prefix, e.g. swift.wrapper.APP-UUID; env NATS_SUBJECT_PREFIX")
	fs.StringVar(&cfg.Namespace, "namespace", cfg.Namespace, "subject namespace used with -app")
	fs.DurationVar(&cfg.Timeout, "timeout", cfg.Timeout, "request/reply timeout")
}

func (cfg commonConfig) connect() (*nats.Conn, error) {
	servers := strings.TrimSpace(cfg.Servers)
	if servers == "" {
		servers = defaultNATSURL
	}
	options := []nats.Option{
		nats.Name(strings.TrimSpace(cfg.ClientName)),
		nats.Timeout(cfg.Timeout),
	}
	if cfg.TLS || cfg.TLSInsecure {
		options = append(options, nats.Secure(&tls.Config{
			MinVersion:         tls.VersionTLS12,
			InsecureSkipVerify: cfg.TLSInsecure,
		}))
	}
	if cfg.CredsPath != "" {
		options = append(options, nats.UserCredentials(expandPath(cfg.CredsPath)))
	}
	if cfg.Token != "" {
		options = append(options, nats.Token(cfg.Token))
	}
	if cfg.User != "" || cfg.Password != "" {
		options = append(options, nats.UserInfo(cfg.User, cfg.Password))
	}
	return nats.Connect(servers, options...)
}

func (cfg commonConfig) subjects() (subjectSet, error) {
	prefix, err := cfg.subjectPrefix()
	if err != nil {
		return subjectSet{}, err
	}
	return subjectSet{
		Prefix:      prefix,
		Frames:      prefix + ".screen.frames",
		Meta:        prefix + ".screen.meta",
		Events:      prefix + ".screen.events",
		Responses:   prefix + ".events.responses",
		Status:      prefix + ".status",
		Telemetry:   prefix + ".telemetry.status",
		CommandRoot: prefix + ".commands",
	}, nil
}

func (cfg commonConfig) subjectPrefix() (string, error) {
	if prefix := normalizeSubject(strings.TrimSpace(cfg.Prefix)); prefix != "" {
		return prefix, nil
	}
	appUUID := strings.TrimSpace(cfg.AppUUID)
	if appUUID == "" {
		return "", errors.New("either -app or -prefix is required")
	}
	namespace := normalizeSubject(strings.TrimSpace(cfg.Namespace))
	if namespace == "" {
		namespace = defaultNamespace
	}
	return namespace + "." + appUUID, nil
}

func commandSubject(subjects subjectSet, action string) string {
	action = strings.Trim(strings.TrimSpace(action), ".")
	return subjects.CommandRoot + "." + action
}

func normalizeSubject(value string) string {
	return strings.Trim(strings.TrimSpace(value), ".")
}

func firstEnv(keysAndFallback ...string) string {
	if len(keysAndFallback) == 0 {
		return ""
	}
	fallback := keysAndFallback[len(keysAndFallback)-1]
	for _, key := range keysAndFallback[:len(keysAndFallback)-1] {
		if value := os.Getenv(key); value != "" {
			return value
		}
	}
	return fallback
}

func envBool(key string, fallback bool) bool {
	value := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	if value == "" {
		return fallback
	}
	switch value {
	case "1", "true", "yes", "y", "on":
		return true
	case "0", "false", "no", "n", "off":
		return false
	default:
		return fallback
	}
}

func expandPath(path string) string {
	path = os.ExpandEnv(strings.TrimSpace(path))
	if path == "" {
		return ""
	}
	if path == "~" {
		home, _ := os.UserHomeDir()
		if home != "" {
			return home
		}
	}
	if strings.HasPrefix(path, "~/") {
		home, _ := os.UserHomeDir()
		if home != "" {
			return filepath.Join(home, path[2:])
		}
	}
	return path
}

func requestID(action string) string {
	var b [6]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("%s-%d", action, time.Now().UnixNano())
	}
	return action + "-" + hex.EncodeToString(b[:])
}
