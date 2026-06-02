package printercore

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestHelloWorldEposXmlEscapesText(t *testing.T) {
	xml := HelloWorldEposXml(`Hallo <Welt> & "Bon"`, "Wrapper", "Zeile 1\nZeile 2")
	if !strings.Contains(xml, `<epos-print xmlns="http://www.epson-pos.com/schemas/2011/03/epos-print">`) {
		t.Fatalf("expected epos-print root, got %s", xml)
	}
	if !strings.Contains(xml, `Hallo &lt;Welt&gt; &amp; &#34;Bon&#34;`) {
		t.Fatalf("expected escaped title, got %s", xml)
	}
	if !strings.Contains(xml, `Zeile 1&#xA;Zeile 2`) {
		t.Fatalf("expected escaped newline, got %s", xml)
	}
}

func TestEpsonServiceURLDefaults(t *testing.T) {
	got := EpsonServiceURL("10.10.10.131", "", 0)
	want := "http://10.10.10.131/cgi-bin/epos/service.cgi?devid=local_printer&timeout=20000"
	if got != want {
		t.Fatalf("expected %q, got %q", want, got)
	}
}

func TestParseEpsonResponse(t *testing.T) {
	response := parseEpsonResponse(`<response success="true" code="" status="0" xmlns="http://www.epson-pos.com/schemas/2011/03/epos-print" />`)
	if !response.Success {
		t.Fatalf("expected success response")
	}
	if response.Status != "0" {
		t.Fatalf("expected status 0, got %q", response.Status)
	}
}

func TestPrintResponseJSON(t *testing.T) {
	raw := responseJSON(printResponse{Success: true, Code: "OK"})
	var decoded map[string]any
	if err := json.Unmarshal([]byte(raw), &decoded); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	if decoded["success"] != true {
		t.Fatalf("expected success true, got %v", decoded["success"])
	}
}
