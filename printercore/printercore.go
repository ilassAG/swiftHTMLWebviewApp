// Package printercore contains the shared print middleware core used by the
// Android and iOS WebView wrappers.
package printercore

import (
	"bytes"
	"encoding/json"
	"encoding/xml"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const Version = "0.1.0"

const eposNamespace = "http://www.epson-pos.com/schemas/2011/03/epos-print"

type printResponse struct {
	Success      bool   `json:"success"`
	Code         string `json:"code,omitempty"`
	Status       string `json:"status,omitempty"`
	Message      string `json:"message,omitempty"`
	URL          string `json:"url,omitempty"`
	ResponseText string `json:"responseText,omitempty"`
}

// CoreVersion returns the shared printer core version.
func CoreVersion() string {
	return Version
}

// HelloWorldEposFragment returns an Epson ePOS-Print XML fragment. It is the
// shape used by the existing Kassa templates before they are wrapped in
// <epos-print>.
func HelloWorldEposFragment(title string, subtitle string, body string) string {
	if strings.TrimSpace(title) == "" {
		title = "Hallo Welt"
	}
	if strings.TrimSpace(subtitle) == "" {
		subtitle = "swiftHTMLWebviewApp"
	}
	if strings.TrimSpace(body) == "" {
		body = "Go printercore smoke test"
	}

	var builder strings.Builder
	builder.WriteString(`<text align="center"/>`)
	builder.WriteString(`<text dw="true" dh="true" em="true"/>`)
	builder.WriteString(`<text>`)
	builder.WriteString(escapeEposText(title))
	builder.WriteString(`&#10;</text>`)
	builder.WriteString(`<text dw="false" dh="false" em="false"/>`)
	builder.WriteString(`<text>`)
	builder.WriteString(escapeEposText(subtitle))
	builder.WriteString(`&#10;</text>`)
	builder.WriteString(`<feed/>`)
	builder.WriteString(`<text align="left"/>`)
	builder.WriteString(`<text>`)
	builder.WriteString(escapeEposText(body))
	builder.WriteString(`&#10;</text>`)
	builder.WriteString(`<text>`)
	builder.WriteString(escapeEposText(time.Now().Format("2006-01-02 15:04:05")))
	builder.WriteString(`&#10;</text>`)
	builder.WriteString(`<feed/>`)
	builder.WriteString(`<feed/>`)
	builder.WriteString(`<cut type="feed"/>`)
	return builder.String()
}

// HelloWorldEposXml returns a complete <epos-print> document.
func HelloWorldEposXml(title string, subtitle string, body string) string {
	return WrapEposPrint(HelloWorldEposFragment(title, subtitle, body))
}

// WrapEposPrint wraps an ePOS XML fragment in the root Epson ePOS-Print node.
// If the input already contains an epos-print root, it is returned unchanged.
func WrapEposPrint(fragment string) string {
	trimmed := strings.TrimSpace(fragment)
	if strings.HasPrefix(trimmed, "<epos-print") {
		return trimmed
	}
	return `<epos-print xmlns="` + eposNamespace + `">` + fragment + `</epos-print>`
}

// EpsonSoapEnvelope wraps a complete ePOS XML document in Epson's SOAP envelope.
func EpsonSoapEnvelope(eposXml string) string {
	return `<?xml version="1.0" encoding="utf-8"?>` +
		`<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">` +
		`<s:Body>` + WrapEposPrint(eposXml) + `</s:Body>` +
		`</s:Envelope>`
}

// EpsonServiceURL builds the ePOS-Print service endpoint for an Epson printer.
func EpsonServiceURL(host string, devid string, timeoutMs int) string {
	host = strings.TrimSpace(host)
	if host == "" {
		host = "10.10.10.131"
	}
	if !strings.HasPrefix(host, "http://") && !strings.HasPrefix(host, "https://") {
		host = "http://" + host
	}
	devid = strings.TrimSpace(devid)
	if devid == "" {
		devid = "local_printer"
	}
	if timeoutMs <= 0 {
		timeoutMs = 20000
	}

	base := strings.TrimRight(host, "/") + "/cgi-bin/epos/service.cgi"
	values := url.Values{}
	values.Set("devid", devid)
	values.Set("timeout", strconv.Itoa(timeoutMs))
	return base + "?" + values.Encode()
}

// PrintEpsonHelloWorld sends one Hello World test print to an Epson ePOS-Print
// compatible printer and returns a JSON response string for stable mobile
// bindings.
func PrintEpsonHelloWorld(host string, devid string, timeoutMs int, title string, subtitle string, body string) string {
	return PrintEpsonEposXml(host, devid, timeoutMs, HelloWorldEposXml(title, subtitle, body))
}

// PrintEpsonEposXml sends an ePOS XML document or fragment to an Epson printer
// and returns a JSON response string.
func PrintEpsonEposXml(host string, devid string, timeoutMs int, eposXml string) string {
	endpoint := EpsonServiceURL(host, devid, timeoutMs)
	soap := EpsonSoapEnvelope(eposXml)
	client := http.Client{Timeout: timeoutFromMillis(timeoutMs)}
	request, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewBufferString(soap))
	if err != nil {
		return responseJSON(printResponse{Success: false, URL: endpoint, Message: err.Error()})
	}
	request.Header.Set("Content-Type", "text/xml; charset=utf-8")
	request.Header.Set("If-Modified-Since", "Thu, 01 Jan 1970 00:00:00 GMT")

	response, err := client.Do(request)
	if err != nil {
		return responseJSON(printResponse{Success: false, URL: endpoint, Message: err.Error()})
	}
	defer response.Body.Close()

	responseBytes, err := io.ReadAll(response.Body)
	responseText := string(responseBytes)
	if err != nil {
		return responseJSON(printResponse{Success: false, URL: endpoint, Message: err.Error(), ResponseText: responseText})
	}
	if response.StatusCode < 200 || response.StatusCode > 299 {
		return responseJSON(printResponse{
			Success:      false,
			URL:          endpoint,
			Message:      "HTTP " + response.Status,
			ResponseText: responseText,
		})
	}

	parsed := parseEpsonResponse(responseText)
	parsed.URL = endpoint
	parsed.ResponseText = responseText
	if parsed.Message == "" && !parsed.Success && parsed.Code == "" {
		parsed.Message = "Epson response did not report success"
	}
	return responseJSON(parsed)
}

func timeoutFromMillis(timeoutMs int) time.Duration {
	if timeoutMs <= 0 {
		timeoutMs = 20000
	}
	return time.Duration(timeoutMs+5000) * time.Millisecond
}

func parseEpsonResponse(responseText string) printResponse {
	success := attrValue(responseText, "success")
	code := attrValue(responseText, "code")
	status := attrValue(responseText, "status")
	return printResponse{
		Success: success == "true" || success == "1",
		Code:    code,
		Status:  status,
	}
}

func attrValue(text string, name string) string {
	pattern := regexp.MustCompile(name + `\s*=\s*"([^"]*)"`)
	match := pattern.FindStringSubmatch(text)
	if len(match) < 2 {
		return ""
	}
	return match[1]
}

func escapeEposText(value string) string {
	var buffer bytes.Buffer
	if err := xml.EscapeText(&buffer, []byte(value)); err != nil {
		return ""
	}
	return strings.ReplaceAll(buffer.String(), "\n", "&#10;")
}

func responseJSON(response printResponse) string {
	data, err := json.Marshal(response)
	if err != nil {
		return `{"success":false,"message":"printercore JSON encoding failed"}`
	}
	return string(data)
}
