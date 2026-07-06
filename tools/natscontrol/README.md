# NATS Control

Small Go tool for the wrapper NATS remote-management subjects.

It can:

- watch JPEG screen frames on `swift.wrapper.<appUUID>.screen.frames`
- watch screen metadata, stream events, status, and command replies
- watch periodic wrapper telemetry
- serve a local browser viewer for the latest frame and stream stats
- publish `screenStreamStart` / `screenStreamStop` commands
- publish `qrScanImage` jobs from an image file or data URL
- publish arbitrary JSON commands for diagnostics

No credentials are stored by the tool. Pass NATS credentials through CLI flags,
environment variables, or local file paths.

## Build

```sh
cd tools/natscontrol
go test ./...
go build .
```

## Auth And Connection

Common flags:

```text
-server nats://127.0.0.1:4222   NATS URL(s), comma-separated
-creds /path/to/user.creds       NATS .creds file
-token TOKEN                     NATS token
-user USER -password PASS        NATS user/password
-tls                             force TLS
-tls-insecure                    local testing only
-app APP-UUID                    derives swift.wrapper.<APP-UUID>
-prefix swift.wrapper.APP-UUID   explicit subject prefix
```

Environment variables:

```text
NATS_URL
NATS_SERVERS
NATS_CREDS
NATS_TOKEN
NATS_USER
NATS_PASSWORD
NATS_CLIENT_NAME
NATS_APP_UUID
NATS_SUBJECT_PREFIX
NATS_NAMESPACE
```

## Watch Frames

```sh
go run . watch -app APP-UUID -creds /path/to/admin.creds
```

Open:

```text
http://127.0.0.1:18091/
```

Use another port when needed:

```sh
go run . watch -app APP-UUID -http :18100
```

The watcher subscribes to:

```text
swift.wrapper.<appUUID>.screen.frames
swift.wrapper.<appUUID>.screen.meta
swift.wrapper.<appUUID>.screen.events
swift.wrapper.<appUUID>.events.responses
swift.wrapper.<appUUID>.status
swift.wrapper.<appUUID>.telemetry.status
```

## Start NATS Screen Stream

```sh
go run . start -app APP-UUID -creds /path/to/admin.creds \
  -fps 2 -quality 65 -max-width 720
```

This sends a request/reply command to:

```text
swift.wrapper.<appUUID>.commands.screenStreamStart
```

Payload:

```json
{
  "action": "screenStreamStart",
  "source": "app",
  "transport": "nats",
  "subject": "swift.wrapper.<appUUID>.screen.frames",
  "metaSubject": "swift.wrapper.<appUUID>.screen.meta",
  "eventSubject": "swift.wrapper.<appUUID>.screen.events",
  "format": "jpeg",
  "fps": 2,
  "quality": 65,
  "maxWidth": 720
}
```

## Stop NATS Screen Stream

```sh
go run . stop -app APP-UUID -creds /path/to/admin.creds
```

## Send QR Scan Job

```sh
go run . qr -app APP-UUID -creds /path/to/admin.creds -image ./qr.png
go run . qr -app APP-UUID -creds /path/to/admin.creds -image ./qr.png -job-id qr-job-1
```

The tool encodes the image as a `data:image/...;base64,...` payload and sends it
to:

```text
swift.wrapper.<appUUID>.commands.qrScanImage
```

You can also pass a prebuilt data URL:

```sh
go run . qr -app APP-UUID -data-url 'data:image/png;base64,...'
```

## Arbitrary Command

```sh
go run . command -app APP-UUID -action natsStatus -json '{}'
go run . command -app APP-UUID -action settingsGet -json '{}'
go run . command -app APP-UUID -action reload -json '{"reason":"operator"}'
```

For larger payloads:

```sh
go run . command -app APP-UUID -action settingsSet -json-file ./settings-command.json
```

Do not put NATS credentials, app security tokens, or product secrets in JSON
files committed to this repository.
