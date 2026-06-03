package printercore

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	printerKindEpsonEposXML = "epson_epos_xml"
	printerKindEscposRaw    = "escpos_raw"
)

var epsonDiscoveryBodyPattern = regexp.MustCompile(`(?i)(epos|epson|service\.cgi)`)

type discoverOptions struct {
	Hosts         []string
	CIDRs         []string
	TimeoutMs     int
	HTTPTimeoutMs int
	Concurrency   int
	ScanEpson     bool
	ScanEscpos    bool
	EscposPorts   []int
}

type discoveredPrinter struct {
	ID         string `json:"id"`
	Kind       string `json:"kind"`
	Label      string `json:"label"`
	Host       string `json:"host,omitempty"`
	Port       int    `json:"port,omitempty"`
	Local      bool   `json:"local,omitempty"`
	Confidence string `json:"confidence"`
	URL        string `json:"url,omitempty"`
	Message    string `json:"message,omitempty"`
}

type discoverResponse struct {
	Success  bool                `json:"success"`
	Message  string              `json:"message,omitempty"`
	CIDRs    []string            `json:"cidrs,omitempty"`
	Scans    []string            `json:"scans,omitempty"`
	Printers []discoveredPrinter `json:"printers"`
	Warnings []string            `json:"warnings,omitempty"`
}

// DiscoverPrinters scans explicit hosts, explicit CIDRs, or the local IPv4 /24
// networks for printer endpoints. The JSON string argument keeps the gomobile
// API stable while discovery options grow.
func DiscoverPrinters(optionsJSON string) string {
	options, warnings := parseDiscoverOptions(optionsJSON)
	response := discoverResponse{
		Success:  true,
		Printers: []discoveredPrinter{},
		Warnings: warnings,
	}
	if options.ScanEpson {
		response.Scans = append(response.Scans, printerKindEpsonEposXML)
	}
	if options.ScanEscpos {
		response.Scans = append(response.Scans, printerKindEscposRaw)
	}

	hosts := normalizeHosts(options.Hosts)
	cidrs := append([]string{}, options.CIDRs...)
	if len(hosts) == 0 && len(cidrs) == 0 {
		localCIDRs, localWarnings := localIPv4CIDRs()
		cidrs = localCIDRs
		response.Warnings = append(response.Warnings, localWarnings...)
	}
	response.CIDRs = cidrs

	targetSet := make(map[string]struct{})
	for _, host := range hosts {
		targetSet[host] = struct{}{}
	}
	for _, cidr := range cidrs {
		cidrHosts, err := buildTargetsFromCIDR(cidr)
		if err != nil {
			response.Warnings = append(response.Warnings, err.Error())
			continue
		}
		for _, host := range cidrHosts {
			targetSet[host] = struct{}{}
		}
	}

	targets := make([]string, 0, len(targetSet))
	for host := range targetSet {
		targets = append(targets, host)
	}
	sort.Strings(targets)

	if len(targets) == 0 {
		response.Message = "No scan targets were available."
		return discoverResponseJSON(response)
	}
	if !options.ScanEpson && !options.ScanEscpos {
		response.Message = "No printer scan types were enabled."
		return discoverResponseJSON(response)
	}

	response.Printers = scanPrinterTargets(targets, options)
	if len(response.Printers) == 0 {
		response.Message = "No printers found."
	}
	return discoverResponseJSON(response)
}

func parseDiscoverOptions(optionsJSON string) (discoverOptions, []string) {
	options := discoverOptions{
		TimeoutMs:     650,
		HTTPTimeoutMs: 900,
		Concurrency:   96,
		ScanEpson:     true,
		ScanEscpos:    true,
		EscposPorts:   []int{9100},
	}
	warnings := []string{}

	trimmed := strings.TrimSpace(optionsJSON)
	if trimmed == "" {
		return options, warnings
	}

	var raw map[string]any
	if err := json.Unmarshal([]byte(trimmed), &raw); err != nil {
		warnings = append(warnings, "Discovery options JSON could not be parsed: "+err.Error())
		return options, warnings
	}

	options.Hosts = append(options.Hosts, hostsFromAny(raw["host"])...)
	options.Hosts = append(options.Hosts, hostsFromAny(raw["hosts"])...)
	options.CIDRs = append(options.CIDRs, hostsFromAny(raw["cidr"])...)
	options.CIDRs = append(options.CIDRs, hostsFromAny(raw["cidrs"])...)
	options.TimeoutMs = intOption(raw, "timeoutMs", options.TimeoutMs)
	options.HTTPTimeoutMs = intOption(raw, "httpTimeoutMs", options.HTTPTimeoutMs)
	options.Concurrency = intOption(raw, "concurrency", options.Concurrency)
	options.ScanEpson = boolOption(raw, "scanEpson", options.ScanEpson)
	options.ScanEscpos = boolOption(raw, "scanEscpos", options.ScanEscpos)
	options.EscposPorts = portsFromAny(raw["escposPorts"], options.EscposPorts)

	if options.TimeoutMs < 100 {
		options.TimeoutMs = 100
	}
	if options.HTTPTimeoutMs < 100 {
		options.HTTPTimeoutMs = 100
	}
	if options.Concurrency < 1 {
		options.Concurrency = 1
	}
	if options.Concurrency > 256 {
		options.Concurrency = 256
	}

	return options, warnings
}

func scanPrinterTargets(targets []string, options discoverOptions) []discoveredPrinter {
	jobs := make(chan string)
	results := make(chan discoveredPrinter)
	var workers sync.WaitGroup

	workerCount := options.Concurrency
	if workerCount > len(targets) {
		workerCount = len(targets)
	}
	if workerCount < 1 {
		workerCount = 1
	}

	for i := 0; i < workerCount; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for host := range jobs {
				if options.ScanEpson {
					if printer, ok := probeEpsonEposXML(host, time.Duration(options.HTTPTimeoutMs)*time.Millisecond); ok {
						results <- printer
					}
				}
				if options.ScanEscpos {
					for _, port := range options.EscposPorts {
						if printer, ok := probeEscposRaw(host, port, time.Duration(options.TimeoutMs)*time.Millisecond); ok {
							results <- printer
						}
					}
				}
			}
		}()
	}

	go func() {
		for _, target := range targets {
			jobs <- target
		}
		close(jobs)
		workers.Wait()
		close(results)
	}()

	found := make(map[string]discoveredPrinter)
	for printer := range results {
		found[printer.ID] = printer
	}

	printers := make([]discoveredPrinter, 0, len(found))
	for _, printer := range found {
		printers = append(printers, printer)
	}
	sortDiscoveredPrinters(printers)
	return printers
}

func probeEpsonEposXML(host string, timeout time.Duration) (discoveredPrinter, bool) {
	endpoint := epsonDiscoveryURL(host)
	client := http.Client{Timeout: timeout}
	request, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return discoveredPrinter{}, false
	}
	request.Header.Set("If-Modified-Since", "Thu, 01 Jan 1970 00:00:00 GMT")

	response, err := client.Do(request)
	if err != nil {
		return discoveredPrinter{}, false
	}
	defer response.Body.Close()

	bodyBytes, err := io.ReadAll(io.LimitReader(response.Body, 4096))
	if err != nil {
		return discoveredPrinter{}, false
	}
	if !looksLikeEpsonService(response.StatusCode, string(bodyBytes)) {
		return discoveredPrinter{}, false
	}

	return discoveredPrinter{
		ID:         printerID(printerKindEpsonEposXML, host, 80),
		Kind:       printerKindEpsonEposXML,
		Label:      "Epson ePOS-Print",
		Host:       host,
		Port:       80,
		Confidence: "confirmed",
		URL:        endpoint,
	}, true
}

func probeEscposRaw(host string, port int, timeout time.Duration) (discoveredPrinter, bool) {
	if port <= 0 || port > 65535 {
		return discoveredPrinter{}, false
	}
	dialer := net.Dialer{Timeout: timeout}
	connection, err := dialer.Dial("tcp", net.JoinHostPort(host, strconv.Itoa(port)))
	if err != nil {
		return discoveredPrinter{}, false
	}
	_ = connection.Close()

	return discoveredPrinter{
		ID:         printerID(printerKindEscposRaw, host, port),
		Kind:       printerKindEscposRaw,
		Label:      "ESC/POS Raw TCP",
		Host:       host,
		Port:       port,
		Confidence: "probable",
		Message:    "TCP port is open; ESC/POS support is not protocol-confirmed.",
	}, true
}

func looksLikeEpsonService(statusCode int, body string) bool {
	if statusCode != http.StatusOK {
		return false
	}
	trimmed := strings.TrimSpace(body)
	return trimmed == "" || epsonDiscoveryBodyPattern.MatchString(trimmed)
}

func epsonDiscoveryURL(host string) string {
	escapedHost := host
	if strings.Contains(host, ":") && net.ParseIP(host) != nil {
		escapedHost = "[" + host + "]"
	}
	return "http://" + escapedHost + "/cgi-bin/epos/service.cgi"
}

func localIPv4CIDRs() ([]string, []string) {
	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, []string{"Local network interfaces could not be listed: " + err.Error()}
	}

	cidrSet := make(map[string]struct{})
	warnings := []string{}
	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			warnings = append(warnings, "Interface "+iface.Name+" addresses could not be listed: "+err.Error())
			continue
		}
		for _, addr := range addrs {
			ip, _, ok := interfaceIPv4(addr)
			if !ok || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
				continue
			}
			cidrSet[ipv4Slash24(ip)] = struct{}{}
		}
	}

	cidrs := make([]string, 0, len(cidrSet))
	for cidr := range cidrSet {
		cidrs = append(cidrs, cidr)
	}
	sort.Strings(cidrs)
	return cidrs, warnings
}

func interfaceIPv4(addr net.Addr) (net.IP, *net.IPNet, bool) {
	ipNet, ok := addr.(*net.IPNet)
	if !ok {
		return nil, nil, false
	}
	ip := ipNet.IP.To4()
	if ip == nil {
		return nil, nil, false
	}
	return ip, ipNet, true
}

func ipv4Slash24(ip net.IP) string {
	v4 := ip.To4()
	if v4 == nil {
		return ""
	}
	return strconv.Itoa(int(v4[0])) + "." +
		strconv.Itoa(int(v4[1])) + "." +
		strconv.Itoa(int(v4[2])) + ".0/24"
}

func buildTargetsFromCIDR(cidr string) ([]string, error) {
	trimmed := strings.TrimSpace(cidr)
	ip, ipNet, err := net.ParseCIDR(trimmed)
	if err != nil {
		return nil, errWithPrefix("Invalid discovery CIDR "+trimmed, err)
	}
	ip = ip.To4()
	if ip == nil {
		return nil, errText("Discovery only supports IPv4 CIDRs: " + trimmed)
	}

	ones, bits := ipNet.Mask.Size()
	if bits != 32 {
		return nil, errText("Discovery only supports IPv4 CIDRs: " + trimmed)
	}
	if ones < 24 {
		return nil, errText("Discovery CIDR is too broad; use /24 or smaller: " + trimmed)
	}

	var hosts []string
	start := ipToUint32(ip.Mask(ipNet.Mask))
	end := start | ^ipToUint32(net.IP(ipNet.Mask))
	for value := start + 1; value < end; value++ {
		hostIP := uint32ToIP(value)
		if ipNet.Contains(hostIP) {
			hosts = append(hosts, hostIP.String())
		}
	}
	sort.Strings(hosts)
	return hosts, nil
}

func normalizeHosts(hosts []string) []string {
	hostSet := make(map[string]struct{})
	for _, raw := range hosts {
		for _, part := range splitHostList(raw) {
			host := normalizeHost(part)
			if host != "" {
				hostSet[host] = struct{}{}
			}
		}
	}

	normalized := make([]string, 0, len(hostSet))
	for host := range hostSet {
		normalized = append(normalized, host)
	}
	sort.Strings(normalized)
	return normalized
}

func splitHostList(raw string) []string {
	return strings.FieldsFunc(raw, func(r rune) bool {
		return r == ',' || r == ';' || r == '\n' || r == '\t' || r == ' '
	})
}

func normalizeHost(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}
	if strings.Contains(trimmed, "://") {
		parsed, err := url.Parse(trimmed)
		if err == nil && parsed.Hostname() != "" {
			return parsed.Hostname()
		}
	}
	trimmed = strings.TrimPrefix(trimmed, "//")
	if slash := strings.Index(trimmed, "/"); slash >= 0 {
		trimmed = trimmed[:slash]
	}
	if host, _, err := net.SplitHostPort(trimmed); err == nil {
		return strings.Trim(host, "[]")
	}
	return strings.Trim(trimmed, "[]")
}

func hostsFromAny(value any) []string {
	switch typed := value.(type) {
	case string:
		return []string{typed}
	case []any:
		var hosts []string
		for _, item := range typed {
			if raw, ok := item.(string); ok {
				hosts = append(hosts, raw)
			}
		}
		return hosts
	default:
		return nil
	}
}

func portsFromAny(value any, fallback []int) []int {
	rawPorts, ok := value.([]any)
	if !ok {
		return fallback
	}

	var ports []int
	for _, raw := range rawPorts {
		port := 0
		switch typed := raw.(type) {
		case float64:
			port = int(typed)
		case string:
			parsed, err := strconv.Atoi(strings.TrimSpace(typed))
			if err == nil {
				port = parsed
			}
		}
		if port > 0 && port <= 65535 {
			ports = append(ports, port)
		}
	}
	if len(ports) == 0 {
		return fallback
	}
	return ports
}

func intOption(raw map[string]any, key string, fallback int) int {
	value, ok := raw[key]
	if !ok {
		return fallback
	}
	switch typed := value.(type) {
	case float64:
		return int(typed)
	case string:
		parsed, err := strconv.Atoi(strings.TrimSpace(typed))
		if err == nil {
			return parsed
		}
	}
	return fallback
}

func boolOption(raw map[string]any, key string, fallback bool) bool {
	value, ok := raw[key]
	if !ok {
		return fallback
	}
	switch typed := value.(type) {
	case bool:
		return typed
	case string:
		parsed, err := strconv.ParseBool(strings.TrimSpace(typed))
		if err == nil {
			return parsed
		}
	}
	return fallback
}

func printerID(kind string, host string, port int) string {
	cleanHost := regexp.MustCompile(`[^a-zA-Z0-9_.-]+`).ReplaceAllString(host, "-")
	return kind + "-" + cleanHost + "-" + strconv.Itoa(port)
}

func sortDiscoveredPrinters(printers []discoveredPrinter) {
	kindRank := map[string]int{
		printerKindEpsonEposXML: 10,
		printerKindEscposRaw:    20,
	}
	sort.Slice(printers, func(i int, j int) bool {
		left := printers[i]
		right := printers[j]
		if kindRank[left.Kind] != kindRank[right.Kind] {
			return kindRank[left.Kind] < kindRank[right.Kind]
		}
		if left.Host != right.Host {
			return left.Host < right.Host
		}
		return left.Port < right.Port
	})
}

func ipToUint32(ip net.IP) uint32 {
	v4 := ip.To4()
	return uint32(v4[0])<<24 | uint32(v4[1])<<16 | uint32(v4[2])<<8 | uint32(v4[3])
}

func uint32ToIP(value uint32) net.IP {
	return net.IPv4(byte(value>>24), byte(value>>16), byte(value>>8), byte(value))
}

func discoverResponseJSON(response discoverResponse) string {
	data, err := json.Marshal(response)
	if err != nil {
		return `{"success":false,"message":"printercore discovery JSON encoding failed","printers":[]}`
	}
	return string(data)
}

type discoveryError string

func (err discoveryError) Error() string {
	return string(err)
}

func errText(message string) error {
	return discoveryError(message)
}

func errWithPrefix(prefix string, err error) error {
	return discoveryError(prefix + ": " + err.Error())
}
