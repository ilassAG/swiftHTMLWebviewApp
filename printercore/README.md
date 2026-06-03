# printercore

Shared Go print middleware core for the WebView wrapper.

The first spike supports Epson ePOS-Print Hello World jobs and shared printer
discovery so the same Go code can be tested before it is packaged for Android
and iOS.

```sh
go test ./...
go run ./cmd/pmprint -dry-run
go run ./cmd/pmprint -host <printer-ip>
```

`DiscoverPrinters(optionsJSON)` accepts a JSON string and returns a JSON result
for mobile bindings. With no explicit `hosts` or `cidrs`, it scans the local
IPv4 `/24` networks for:

- confirmed Epson ePOS-Print XML endpoints at `/cgi-bin/epos/service.cgi`
- probable raw ESC/POS TCP printers on port `9100`

ESC/POS discovery only opens a TCP connection. It does not send bytes or print.
