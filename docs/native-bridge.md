# Native Bridge

The wrapper exposes native features to web content through WebKit message handlers.

## Message handler

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'scanBarcode',
  requestId: crypto.randomUUID()
});
```

Native code answers by calling:

```js
window.handleNativeResult(result)
```

Each request should include a `requestId` when the web app needs to correlate asynchronous responses.

## Common response shape

Success:

```json
{
  "action": "scanBarcode",
  "requestId": "...",
  "code": "..."
}
```

Error:

```json
{
  "action": "scanBarcode",
  "requestId": "...",
  "error": "Human-readable error"
}
```

## Built-in actions

- `scanDocument`
- `takePhoto`
- `scanBarcode`
- `launchConfetti`
- `tapToPayAvailability` (optional Stripe module)
- `tapToPayCollect` (optional Stripe module)

Platform implementations should keep this web-facing API stable even when native code differs between iOS and Android.
