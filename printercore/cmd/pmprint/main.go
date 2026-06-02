package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/ilass/swifthtmlwebviewapp/printercore"
)

func main() {
	host := flag.String("host", "10.10.10.131", "Epson ePOS printer host or base URL")
	devid := flag.String("devid", "local_printer", "Epson device id")
	timeout := flag.Int("timeout", 20000, "Epson ePOS timeout in milliseconds")
	title := flag.String("title", "Hallo Welt", "headline")
	subtitle := flag.String("subtitle", "swiftHTMLWebviewApp", "subtitle")
	body := flag.String("body", "Go printercore smoke test", "body text")
	dryRun := flag.Bool("dry-run", false, "print generated XML instead of sending it")
	flag.Parse()

	xml := printercore.HelloWorldEposXml(*title, *subtitle, *body)
	if *dryRun {
		fmt.Println(xml)
		return
	}

	raw := printercore.PrintEpsonEposXml(*host, *devid, *timeout, xml)
	fmt.Println(raw)
	var result struct {
		Success bool   `json:"success"`
		Message string `json:"message"`
		Code    string `json:"code"`
	}
	if err := json.Unmarshal([]byte(raw), &result); err != nil {
		fmt.Fprintln(os.Stderr, "could not parse printer response:", err)
		os.Exit(1)
	}
	if !result.Success {
		if result.Message != "" {
			fmt.Fprintln(os.Stderr, result.Message)
		}
		if result.Code != "" {
			fmt.Fprintln(os.Stderr, "printer code:", result.Code)
		}
		os.Exit(1)
	}
}
