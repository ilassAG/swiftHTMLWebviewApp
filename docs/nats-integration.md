# NATS Integration

Status: first native implementation landed for the generic wrapper.
Last updated: 2026-07-06.

This document defines the configuration and security model for native NATS
without leaking NATS secrets into the WebView, UserDefaults, `appConfig`, logs,
or source control.

Implemented first pass:

- iOS: `nats.swift` transport, Keychain credential storage, redacted status,
  command subscription, publish support.
- Android: JNATS transport, Android-Keystore-encrypted credential storage,
  redacted status, command subscription, publish support.
- Command subject: `swift.wrapper.<appUUID>.commands.*`.
- Initial remote commands: `status`, `settings`, `settingsSet`, `screenshot`,
  `qrScanImage`, `screenStreamStart`, `screenStreamStop`, `reload`, and
  `natsStatus`.

Not in the first pass: arbitrary web-exposed subscribe/unsubscribe, NATS screen
video transport, and automatic NATS user provisioning.

## Infrastructure Boundary

The open-source wrapper does not define production NATS hosts. Product variants
or provisioning backends must provide the actual server URLs and credentials.

Client connections should usually use:

- `tls://...:4222`
- TLS handshake-first
- one or more configured URLs for reconnect/failover
- per-device NATS credentials where possible

Production deployments should prefer NATS `.creds` authentication. Other auth
modes may be supported by the generic wrapper, but production devices should be
provisioned with `.creds` unless there is a deliberate reason not to.

## Existing Wrapper Identity

The wrapper now has `appUUID` as a read-only, stable native installation UUID.
It is generated once per app installation and is returned by `settingsGet`,
`deviceInfoGet`, and config-pairing identity payloads.

Use `appUUID` as the stable NATS-side installation identifier.

Do not use `deviceUUID` as the primary NATS identity. `deviceUUID` is a
deployment/device setting and remains writable through settings/config flows.
It is useful for business/domain identity, but it is not the immutable native
installation key.

Recommended NATS client name:

```text
swift-wrapper-${appUUID}
```

The client name is only for logs/monitoring. It is not authentication. Real
authentication comes from NATS credentials and, where needed, higher-level
application policy.

## Security Boundary

The WebView may start provisioning and display status, but it must not own NATS
secrets.

Responsibilities:

| Layer | Responsibility |
| --- | --- |
| Web app | Starts provisioning, shows status, requests connect/disconnect/publish/subscribe through the native bridge. |
| Native wrapper | Stores NATS secrets in Keychain, opens the NATS connection, redacts sensitive status. |
| Provisioning backend/admin tool | Authenticates the user/admin, creates or assigns NATS users, issues short-lived provisioning payloads. |
| NATS cluster | Accepts only valid credentials and enforces subject permissions. |

Never return these values through `settingsGet`, `deviceInfoGet`, `appConfig`,
JavaScript callbacks, logs, screenshots, or recovery pages:

- `.creds` content
- NKey seed
- JWT
- token
- password
- private key
- client certificate private key / PKCS#12 bytes

Secrets should go to the iOS Keychain. Android should use the Android Keystore
or encrypted credential storage when parity is implemented.

## What A NATS `.creds` File Is

A NATS `.creds` file contains:

1. a signed user JWT, containing user/account/permission metadata
2. the user's private NKey seed, used to sign the server challenge

It is not just a hash or signature. Treat it as a private key bundle.

The server must not auto-create users just because a wrapper presents an
`appUUID`. Users/credentials should be created only by a controlled
provisioning flow.

## Configuration Model

Add a dedicated native NATS config object rather than storing NATS fields as
ad-hoc `appConfig` keys.

Suggested persisted non-secret settings:

```json
{
  "nats": {
    "enabled": true,
    "urls": [
      "tls://nats.example.invalid:4222"
    ],
    "tlsFirst": true,
    "clientNameTemplate": "swift-wrapper-${appUUID}",
    "identitySource": "appUUID",
    "auth": {
      "method": "creds",
      "credentialRef": "keychain:nats.creds"
    },
    "reconnect": {
      "maxReconnects": -1,
      "reconnectWaitMs": 500,
      "pingIntervalSeconds": 10
    },
    "subjects": {
      "namespace": "swift.wrapper",
      "devicePrefixTemplate": "swift.wrapper.${appUUID}"
    }
  }
}
```

For the generic wrapper, default values should keep NATS disabled and leave
server URLs empty until provisioning supplies them:

```json
{
  "enabled": false,
  "urls": [],
  "tlsFirst": true,
  "clientNameTemplate": "swift-wrapper-${appUUID}",
  "identitySource": "appUUID",
  "auth": {
    "method": "creds",
    "credentialRef": "keychain:nats.creds"
  }
}
```

`settingsGet` should return only a redacted snapshot:

```json
{
  "nats": {
    "enabled": true,
    "urls": ["tls://nats.example.invalid:4222"],
    "tlsFirst": true,
    "clientName": "swift-wrapper-APP-UUID",
    "identitySource": "appUUID",
    "auth": {
      "method": "creds",
      "credentialSet": true
    },
    "connected": true,
    "lastError": ""
  }
}
```

Do not include `credentialRef` in public snapshots unless it is explicitly
redacted and cannot be used to retrieve the secret from JavaScript.

## Auth Methods To Model

The generic wrapper can model common NATS auth methods with one enum:

```text
none
token
userPassword
nkey
creds
tlsCertificate
```

Recommended storage mapping:

| Method | Non-secret config | Secret storage |
| --- | --- | --- |
| `none` | method only; dev/local only | none |
| `token` | method, optional token label | token in Keychain |
| `userPassword` | username may be non-secret | password in Keychain |
| `nkey` | public NKey optional | NKey seed in Keychain |
| `creds` | method, credential present flag | full `.creds` content in Keychain |
| `tlsCertificate` | certificate label/fingerprint | private key or PKCS#12 in Keychain |

Production should prefer `creds`.

## Provisioning Workflow

Preferred online workflow:

1. User installs and opens the wrapper.
2. Default bundled/configurator web page reads `settingsGet` and obtains the
   read-only `appUUID`.
3. User authenticates or scans an admin/pairing code.
4. Provisioning backend verifies that the user may enroll this installation.
5. Backend creates or assigns a NATS user for this `appUUID`.
6. Backend returns a one-time provisioning response containing NATS config and
   credentials.
7. Web app passes that response to the native bridge action `natsProvision`.
8. Native code stores secrets in Keychain, persists non-secret config in native
   settings, and connects to the cluster.
9. `settingsGet`, `natsStatus`, or `deviceInfoGet` reports NATS status with
   secrets redacted.

The provisioning token/code should be short-lived and single-use. Do not build
an endpoint that creates NATS users for arbitrary unauthenticated `appUUID`
values.

Offline/local-admin workflow:

1. Admin device or setup tool creates the device NATS credentials.
2. Credentials are transferred to the target wrapper through BLE config pairing
   or another local secure channel.
3. Target native code stores credentials directly in Keychain.
4. The credentials are never shown again through the WebView.

Direct QR with full `.creds` content is technically possible but discouraged:
the content is sensitive and may be too large. Prefer QR carrying a one-time
provisioning code, not the final private credential.

## Proposed Bridge Actions

Add NATS-specific actions instead of overloading generic settings:

### `natsProvision`

Stores NATS config and secrets.

Input shape:

```json
{
  "action": "natsProvision",
  "requestId": "req-1",
  "token": "current-wrapper-security-token",
  "nats": {
    "enabled": true,
    "urls": [
      "tls://nats.example.invalid:4222"
    ],
    "tlsFirst": true,
    "auth": {
      "method": "creds",
      "creds": "-----BEGIN NATS USER JWT-----\\n...\\n------END NATS USER NKEY SEED------"
    }
  }
}
```

Native behavior:

- require the current wrapper `securityToken`
- validate URL schemes and auth method
- store secret fields in Keychain
- clear secret fields from any in-memory response/logging payload
- persist only non-secret fields
- optionally connect immediately

Response shape:

```json
{
  "action": "natsProvision",
  "requestId": "req-1",
  "success": true,
  "nats": {
    "enabled": true,
    "auth": {
      "method": "creds",
      "credentialSet": true
    }
  }
}
```

### `natsStatus`

Returns redacted connection state.

```json
{
  "action": "natsStatus",
  "requestId": "req-2"
}
```

Response:

```json
{
  "action": "natsStatus",
  "requestId": "req-2",
  "success": true,
  "connected": true,
  "clientName": "swift-wrapper-APP-UUID",
  "servers": [
    {"url": "tls://nats.example.invalid:4222", "lastState": "connected"}
  ],
  "auth": {
    "method": "creds",
    "credentialSet": true
  }
}
```

### `natsConnect` / `natsDisconnect`

Explicitly starts or stops the native NATS client. The wrapper may also connect
automatically on launch when `nats.enabled` is true and credentials are present.

### `natsPublish`

Publishes a web-provided payload through native NATS. This should be permission
limited by both bridge policy and NATS subject permissions.

Input:

```json
{
  "action": "natsPublish",
  "requestId": "req-3",
  "subject": "swift.wrapper.APP-UUID.status",
  "json": {"ok": true}
}
```

### `natsSubscribe` / `natsUnsubscribe`

Optional. Only expose if the web app actually needs direct NATS events. For
many management features, native code should subscribe internally and emit
specific bridge events instead of exposing arbitrary subjects to JavaScript.

## Subject And Permission Guidance

Do not grant broad `>` permissions to app devices.

Example per-install subject namespace:

```text
swift.wrapper.<appUUID>.status
swift.wrapper.<appUUID>.events.*
swift.wrapper.<appUUID>.commands.*
swift.wrapper.<appUUID>.screen.frames
swift.wrapper.<appUUID>.screen.meta
```

Example client permissions:

| Direction | Subjects |
| --- | --- |
| publish | `swift.wrapper.<appUUID>.status`, `swift.wrapper.<appUUID>.events.*`, `swift.wrapper.<appUUID>.screen.*` |
| subscribe | `swift.wrapper.<appUUID>.commands.*` |

Management/backend users can have broader permissions, but mobile app
credentials should be narrow and revocable.

## Screen Streaming Over NATS

The screen stream supports WebSocket and NATS transports. WebSocket remains
available for local tools:

```json
{
  "action": "screenStreamStart",
  "transport": "websocket",
  "targetUrl": "ws://..."
}
```

NATS transport publishes binary JPEG frames to a device-scoped frame subject and
JSON metadata/events to companion subjects:

```json
{
  "action": "screenStreamStart",
  "transport": "nats",
  "subject": "swift.wrapper.${appUUID}.screen.frames",
  "metaSubject": "swift.wrapper.${appUUID}.screen.meta",
  "fps": 2,
  "quality": 0.65,
  "maxWidth": 720
}
```

Implementation detail:

- send metadata as JSON on `metaSubject`
- send JPEG bytes on `subject`
- send stream open/error/stats events as JSON on `eventSubject`
- do not include credentials in stream metadata
- rate-limit and stop streaming on disconnect or app background if required by
  platform policy

## QR Image Scan Over NATS

Management backends can distribute QR decoding work to idle or selected devices
by sending a NATS command with an image payload:

```json
{
  "action": "qrScanImage",
  "requestId": "scan-1",
  "dataURL": "data:image/png;base64,..."
}
```

The command also accepts `imageBase64`, `imageData`, or `image`. The reply
contains `success`, `format: "qr"`, `code` for the first match, and `codes` for
all matches the platform decoder returns. The image is decoded in memory only
and is not persisted or echoed back.

## Swift Implementation Notes

Expected new native components:

- `NATSSettings.swift`: parse, validate, redact, persist non-secret settings.
- `NATSKeychainStore.swift`: store/delete/load credential material.
- `NATSClientService.swift`: own connection lifecycle and reconnect behavior.
- `NATSBridge.swift`: bridge actions and response payloads.
- `NATSPayload.swift`: pure payload parsing/response builders for tests.

Current app architecture already favors testable payload/helper structs. Follow
that pattern and add unit tests before wiring into `ContentView`.

Important integration points:

- `AppSettings.configurationSnapshot(includeSensitive:)`: add redacted NATS
  status/settings only.
- `AppSettings.applyConfiguration(_:)`: may accept non-secret NATS config, but
  should not accept/store raw secrets directly unless the call path is the
  dedicated `natsProvision` bridge.
- `ConfigPairingPayload` / `ConfigPairingBridge`: allow provisioning commands to
  pass NATS payloads to the target, but target native code must store secrets in
  Keychain and only return redacted status.
- `DeviceBridge.deviceInfo`: may expose NATS capability and connection status,
  never secrets.
- `ScreenStreamBridge`: add NATS transport only after `NATSClientService` is
  available.

## Tests To Add

iOS unit tests:

- NATS config normalizes URLs and rejects invalid schemes.
- `appUUID` is used in `clientNameTemplate`.
- `settingsGet` redacts credentials.
- `settingsSet` cannot overwrite `appUUID`.
- `natsProvision` requires the current wrapper security token.
- `natsProvision` stores secrets through a mock Keychain store and returns only
  `credentialSet: true`.
- Auth method parsing covers `none`, `token`, `userPassword`, `nkey`, `creds`,
  and `tlsCertificate`.
- Screen-stream NATS payload generation builds subjects from `appUUID` and does
  not include secrets.

Bridge contract/doc tests:

- Add `natsProvision`, `natsStatus`, `natsConnect`, `natsDisconnect`,
  `natsPublish`, and optional subscribe actions to `docs/bridge-contract.json`
  when implemented.
- Add response fixtures to `docs/bridge-response-fixtures.json`.

Android parity:

- Mirror the same config schema.
- Store secrets outside SharedPreferences unless encrypted.
- Keep response names and redaction behavior identical.

## Rollout Plan

1. Add config and Keychain storage types with tests.
2. Add bridge payloads/actions with redacted status only.
3. Add Swift NATS connection spike against a non-production test credential.
4. Wire product-specific cluster defaults in private variants that need NATS.
5. Add provisioning backend/tool support for issuing per-`appUUID` `.creds`.
6. Add NATS screen-stream transport as a separate step.
7. Add Android parity only after the iOS bridge contract is stable.

## Non-Goals For First Implementation

- Do not auto-create NATS users from unauthenticated app launches.
- Do not put NATS credentials in `appConfig`, UserDefaults, local HTML, or
  variant manifests.
- Do not expose arbitrary subscribe/publish to JavaScript without a clear
  subject policy.
- Do not replace existing WebSocket screen streaming in the first NATS pass.
- Do not use `deviceUUID` as the immutable NATS identity.
