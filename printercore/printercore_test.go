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
	got := EpsonServiceURL("192.0.2.10", "", 0)
	want := "http://192.0.2.10/cgi-bin/epos/service.cgi?devid=local_printer&timeout=20000"
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

func TestPrintEpsonEposXmlRequiresHost(t *testing.T) {
	raw := PrintEpsonEposXml("", "local_printer", 20000, HelloWorldEposXml("", "", ""))
	var decoded map[string]any
	if err := json.Unmarshal([]byte(raw), &decoded); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	if decoded["success"] != false {
		t.Fatalf("expected success false, got %v", decoded["success"])
	}
	if decoded["message"] != "printer host is required" {
		t.Fatalf("unexpected message: %v", decoded["message"])
	}
}

func TestLooksLikeEpsonService(t *testing.T) {
	cases := []struct {
		name string
		code int
		body string
		want bool
	}{
		{name: "empty ok body", code: 200, body: "", want: true},
		{name: "epson body", code: 200, body: "EPSON ePOS service.cgi", want: true},
		{name: "non epson body", code: 200, body: "plain web server", want: false},
		{name: "wrong status", code: 404, body: "EPSON", want: false},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			got := looksLikeEpsonService(test.code, test.body)
			if got != test.want {
				t.Fatalf("expected %v, got %v", test.want, got)
			}
		})
	}
}

func TestNormalizeHosts(t *testing.T) {
	got := normalizeHosts([]string{
		"192.0.2.10, http://192.0.2.11/cgi-bin/epos/service.cgi",
		"192.0.2.10:9100",
		"[2001:db8::10]:9100",
	})
	want := []string{"192.0.2.10", "192.0.2.11", "2001:db8::10"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("expected %v, got %v", want, got)
	}
}

func TestBuildTargetsFromCIDR(t *testing.T) {
	got, err := buildTargetsFromCIDR("192.0.2.0/30")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{"192.0.2.1", "192.0.2.2"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("expected %v, got %v", want, got)
	}
}

func TestDiscoverPrintersWithoutEnabledScans(t *testing.T) {
	raw := DiscoverPrinters(`{"hosts":["192.0.2.10"],"scanEpson":false,"scanEscpos":false}`)
	var decoded map[string]any
	if err := json.Unmarshal([]byte(raw), &decoded); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	if decoded["success"] != true {
		t.Fatalf("expected success true, got %v", decoded["success"])
	}
	if decoded["message"] != "No printer scan types were enabled." {
		t.Fatalf("unexpected message: %v", decoded["message"])
	}
}
