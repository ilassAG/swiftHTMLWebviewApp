# printercore

Shared Go print middleware core for the WebView wrapper.

The first spike supports an Epson ePOS-Print Hello World job so the same Go
code can be tested before it is packaged for Android and iOS.

```sh
go test ./...
go run ./cmd/pmprint -dry-run
go run ./cmd/pmprint -host 10.10.10.131
```
