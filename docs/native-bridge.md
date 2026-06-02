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
- `printerEpsonHelloWorld` (optional Go printer core)

## Printer smoke test

`printerEpsonHelloWorld` sends one small Epson ePOS-Print job to a network printer.
It is implemented through the shared Go `printercore` package and is currently a
smoke-test bridge for the later receipt-printer middleware.

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'printerEpsonHelloWorld',
  requestId: crypto.randomUUID(),
  host: '10.10.10.131',
  devid: 'local_printer',
  timeoutMs: 20000,
  title: 'Hallo Welt',
  subtitle: 'swiftHTMLWebviewApp',
  body: 'Bridge test'
});
```

Typical success response:

```json
{
  "platform": "ios",
  "action": "printerEpsonHelloWorld",
  "success": true,
  "host": "10.10.10.131",
  "devid": "local_printer",
  "goCoreVersion": "0.1.0",
  "status": "251658262"
}
```

Regenerate the mobile bindings after changing `printercore`:

```sh
printercore/scripts/build_mobile.sh
```

Platform implementations should keep this web-facing API stable even when native code differs between iOS and Android.
