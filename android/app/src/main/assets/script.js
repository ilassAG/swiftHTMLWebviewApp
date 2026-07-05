// Filename: HTML/script.js

document.addEventListener('DOMContentLoaded', () => {
    // --- Elemente holen ---
    const scanDocPdfBtn = document.getElementById('scanDocPdfBtn');
    const scanDocPngBtn = document.getElementById('scanDocPngBtn');
    const takePhotoFrontBtn = document.getElementById('takePhotoFrontBtn');
    const takePhotoBackBtn = document.getElementById('takePhotoBackBtn');
    const portraitCaptureBtn = document.getElementById('portraitCaptureBtn');
    const portraitCameraSelect = document.getElementById('portraitCameraSelect');
    const portraitFacesInput = document.getElementById('portraitFacesInput');
    const portraitCountdownInput = document.getElementById('portraitCountdownInput');
    const portraitVariationInput = document.getElementById('portraitVariationInput');
    const portraitIntervalInput = document.getElementById('portraitIntervalInput');
    const portraitOutputTypeSelect = document.getElementById('portraitOutputTypeSelect');
    const portraitCropSelect = document.getElementById('portraitCropSelect');
    const portraitRemoveBackgroundCheckbox = document.getElementById('portraitRemoveBackgroundCheckbox');
    const portraitBackgroundMode = document.getElementById('portraitBackgroundMode');
    const portraitBackgroundColor = document.getElementById('portraitBackgroundColor');
    const portraitCropTransparentCheckbox = document.getElementById('portraitCropTransparentCheckbox');
    const portraitMirrorOutputCheckbox = document.getElementById('portraitMirrorOutputCheckbox');
    const removeBackgroundCheckbox = document.getElementById('removeBackgroundCheckbox');
    const photoBackgroundMode = document.getElementById('photoBackgroundMode');
    const photoBackgroundColor = document.getElementById('photoBackgroundColor');
    const cropTransparentCheckbox = document.getElementById('cropTransparentCheckbox');
    const confettiBtn = document.getElementById('confettiBtn');
    const scanBarcodeBtn = document.getElementById('scanBarcodeBtn');
    const nfcTagReadBtn = document.getElementById('nfcTagReadBtn');
    const scannerModeSelect = document.getElementById('scannerModeSelect');
    const scannerCameraSelect = document.getElementById('scannerCameraSelect');
    const scannerTopInput = document.getElementById('scannerTopInput');
    const scannerLeftInput = document.getElementById('scannerLeftInput');
    const scannerWidthInput = document.getElementById('scannerWidthInput');
    const scannerHeightInput = document.getElementById('scannerHeightInput');
    const permanentScanStartBtn = document.getElementById('permanentScanStartBtn');
    const permanentScanUpdateBtn = document.getElementById('permanentScanUpdateBtn');
    const permanentScanStopBtn = document.getElementById('permanentScanStopBtn');
    const beaconUuidInput = document.getElementById('beaconUuidInput');
    const beaconsStartBtn = document.getElementById('beaconsStartBtn');
    const beaconsStopBtn = document.getElementById('beaconsStopBtn');
    const beaconAdvertiseUuidInput = document.getElementById('beaconAdvertiseUuidInput');
    const beaconAdvertiseMajorInput = document.getElementById('beaconAdvertiseMajorInput');
    const beaconAdvertiseMinorInput = document.getElementById('beaconAdvertiseMinorInput');
    const beaconAdvertiseStartBtn = document.getElementById('beaconAdvertiseStartBtn');
    const beaconAdvertiseStopBtn = document.getElementById('beaconAdvertiseStopBtn');
    const orientationSelect = document.getElementById('orientationSelect');
    const orientationSetBtn = document.getElementById('orientationSetBtn');
    const wifiSsidInput = document.getElementById('wifiSsidInput');
    const wifiPasswordInput = document.getElementById('wifiPasswordInput');
    const configPairingPayloadInput = document.getElementById('configPairingPayloadInput');
    const configSecurityTokenInput = document.getElementById('configSecurityTokenInput');
    const configNewSecurityTokenInput = document.getElementById('configNewSecurityTokenInput');
    const configAppUuidOutput = document.getElementById('configAppUuidOutput');
    const configDeviceNameInput = document.getElementById('configDeviceNameInput');
    const configDeviceUuidInput = document.getElementById('configDeviceUuidInput');
    const configDeviceLocationInput = document.getElementById('configDeviceLocationInput');
    const configServerUrlInput = document.getElementById('configServerUrlInput');
    const configHaEnabledInput = document.getElementById('configHaEnabledInput');
    const configHaTimeoutInput = document.getElementById('configHaTimeoutInput');
    const configUrl2Input = document.getElementById('configUrl2Input');
    const configUrl3Input = document.getElementById('configUrl3Input');
    const configUrl4Input = document.getElementById('configUrl4Input');
    const configBeaconUuidInput = document.getElementById('configBeaconUuidInput');
    const configWifiSsidInput = document.getElementById('configWifiSsidInput');
    const configWifiPasswordInput = document.getElementById('configWifiPasswordInput');
    const configPairingShowBtn = document.getElementById('configPairingShowBtn');
    const configPairingStopBtn = document.getElementById('configPairingStopBtn');
    const configPairingScanBtn = document.getElementById('configPairingScanBtn');
    const configPairingConnectBtn = document.getElementById('configPairingConnectBtn');
    const configPairingDisconnectBtn = document.getElementById('configPairingDisconnectBtn');
    const localSettingsGetBtn = document.getElementById('localSettingsGetBtn');
    const localSettingsSetBtn = document.getElementById('localSettingsSetBtn');
    const configStatusBtn = document.getElementById('configStatusBtn');
    const configSettingsGetBtn = document.getElementById('configSettingsGetBtn');
    const configSettingsSetBtn = document.getElementById('configSettingsSetBtn');
    const configWifiConfigureBtn = document.getElementById('configWifiConfigureBtn');
    const configReloadBtn = document.getElementById('configReloadBtn');
    const deviceInfoBtn = document.getElementById('deviceInfoBtn');
    const wifiStatusBtn = document.getElementById('wifiStatusBtn');
    const wifiConfigureBtn = document.getElementById('wifiConfigureBtn');
    const screenshotBtn = document.getElementById('screenshotBtn');
    const geoGetBtn = document.getElementById('geoGetBtn');
    const geoStartBtn = document.getElementById('geoStartBtn');
    const geoStopBtn = document.getElementById('geoStopBtn');
    const soundPlayBtn = document.getElementById('soundPlayBtn');
    const notificationPermissionBtn = document.getElementById('notificationPermissionBtn');
    const notificationShowBtn = document.getElementById('notificationShowBtn');
    const notificationScheduleBtn = document.getElementById('notificationScheduleBtn');
    const notificationCancelBtn = document.getElementById('notificationCancelBtn');
    const idleTimeoutInput = document.getElementById('idleTimeoutInput');
    const idleIntervalInput = document.getElementById('idleIntervalInput');
    const idleStartBtn = document.getElementById('idleStartBtn');
    const idleResetBtn = document.getElementById('idleResetBtn');
    const idleStopBtn = document.getElementById('idleStopBtn');
    const sensorCapabilitiesBtn = document.getElementById('sensorCapabilitiesBtn');
    const sensorStartBtn = document.getElementById('sensorStartBtn');
    const sensorStopBtn = document.getElementById('sensorStopBtn');
    const screenStreamTargetInput = document.getElementById('screenStreamTargetInput');
    const screenStreamFpsInput = document.getElementById('screenStreamFpsInput');
    const screenStreamWidthInput = document.getElementById('screenStreamWidthInput');
    const screenStreamStartBtn = document.getElementById('screenStreamStartBtn');
    const screenStreamStopBtn = document.getElementById('screenStreamStopBtn');
    const storageNamespaceInput = document.getElementById('storageNamespaceInput');
    const storageKeyInput = document.getElementById('storageKeyInput');
    const storageValueInput = document.getElementById('storageValueInput');
    const storageSetBtn = document.getElementById('storageSetBtn');
    const storageGetBtn = document.getElementById('storageGetBtn');
    const storageRemoveBtn = document.getElementById('storageRemoveBtn');
    const storageClearBtn = document.getElementById('storageClearBtn');
    const fileDirectorySelect = document.getElementById('fileDirectorySelect');
    const filePathInput = document.getElementById('filePathInput');
    const fileDataInput = document.getElementById('fileDataInput');
    const fileWriteBtn = document.getElementById('fileWriteBtn');
    const fileReadBtn = document.getElementById('fileReadBtn');
    const fileListBtn = document.getElementById('fileListBtn');
    const fileDeleteBtn = document.getElementById('fileDeleteBtn');
    const sqliteDatabaseInput = document.getElementById('sqliteDatabaseInput');
    const sqliteKeyInput = document.getElementById('sqliteKeyInput');
    const sqliteValueInput = document.getElementById('sqliteValueInput');
    const sqliteInitBtn = document.getElementById('sqliteInitBtn');
    const sqliteUpsertBtn = document.getElementById('sqliteUpsertBtn');
    const sqliteListBtn = document.getElementById('sqliteListBtn');
    const sqliteDeleteDbBtn = document.getElementById('sqliteDeleteDbBtn');
    const kioskOpacityInput = document.getElementById('kioskOpacityInput');
    const kioskLongPressInput = document.getElementById('kioskLongPressInput');
    const kioskReloadEnableBtn = document.getElementById('kioskReloadEnableBtn');
    const kioskReloadDisableBtn = document.getElementById('kioskReloadDisableBtn');
    const printEpsonHelloBtn = document.getElementById('printEpsonHelloBtn');
    const discoverPrintersBtn = document.getElementById('discoverPrintersBtn');
    const epsonPrinterHost = document.getElementById('epsonPrinterHost');
    const printerSelect = document.getElementById('printerSelect');
    const clearResultBtn = document.getElementById('clearResultBtn');

    const statusArea = document.getElementById('statusArea');
    const resultArea = document.getElementById('resultArea');
    const eventLog = document.getElementById('eventLog');
    const placeholderText = document.getElementById('placeholderText');
    const confettiInitialLabel = "Konfetti!";
    const confettiMoreLabel = "mehr Konfetti";
    const debugBridgeMessages = false;
    let discoveredPrinters = [];
    const liveEventActions = new Set([
        "barcodeData",
        "barcodeLogin",
        "beacons",
        "geoLocation",
        "idleTick",
        "idleTimeout",
        "sensorData",
        "screenStreamOpen",
        "screenStreamStats",
        "screenStreamError",
        "screenStreamClosed",
        "configPairingEvent",
        "notificationReceived",
        "notificationOpened"
    ]);
    const commandActions = new Set([
        "screenOrientationSet",
        "wifiConfigure",
        "continuousScanStart",
        "continuousScanStop",
        "dataScanStart",
        "dataScanEnd",
        "loginScanStart",
        "loginScanEnd",
        "previewBoxLocationUpdate",
        "beaconsStart",
        "beaconsStop",
        "beaconAdvertiseStart",
        "beaconAdvertiseStop",
        "settingsGet",
        "settingsSet",
        "geoLocationStart",
        "geoLocationStop",
        "soundPlay",
        "notificationPermissionGet",
        "notificationPermissionRequest",
        "notificationShow",
        "notificationSchedule",
        "notificationCancel",
        "notificationCancelAll",
        "notificationList",
        "idleTimerStart",
        "idleTimerStop",
        "idleTimerReset",
        "sensorStreamStart",
        "sensorStreamStop",
        "screenStreamStart",
        "screenStreamStop",
        "storageGet",
        "storageSet",
        "storageRemove",
        "storageClear",
        "filesystemWrite",
        "filesystemRead",
        "filesystemList",
        "filesystemDelete",
        "sqliteExecute",
        "sqliteDeleteDatabase",
        "kioskReloadControlSet",
        "configPairingShow",
        "configPairingStop",
        "configPairingConnect",
        "configPairingDisconnect",
        "configPairingSend",
        "configPairingResponse"
    ]);

    // --- Event Listeners ---
    scanDocPdfBtn.addEventListener('click', () => {
        const request = {
            action: "scanDocument",
            ocr: true, // Keine OCR für reines PDF
            outputType: "pdf"
        };
        sendBridgeMessage(request);
    });

    scanDocPngBtn.addEventListener('click', () => {
        const request = {
            action: "scanDocument",
            ocr: true, // OCR anfordern
            outputType: "png" // Bilder als PNG
        };
        sendBridgeMessage(request);
    });

    takePhotoFrontBtn.addEventListener('click', () => {
        sendBridgeMessage(createPhotoRequest("front"));
    });

    takePhotoBackBtn.addEventListener('click', () => {
        sendBridgeMessage(createPhotoRequest("back"));
    });

    portraitCaptureBtn?.addEventListener('click', () => {
        sendBridgeMessage(createPortraitCaptureRequest());
    });

    confettiBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "launchConfetti" });
    });

    scanBarcodeBtn.addEventListener('click', () => {
        const request = {
            action: "scanBarcode",
            types: ["qr", "ean13", "ean8", "code128", "datamatrix"]
        };
        sendBridgeMessage(request);
    });

    nfcTagReadBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "nfcTagRead",
            timeoutSeconds: 30
        });
    });

    permanentScanStartBtn?.addEventListener('click', () => {
        sendBridgeMessage(createPermanentScanStartRequest());
    });

    permanentScanUpdateBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "previewBoxLocationUpdate",
            previewRect: createScannerPreviewRect()
        });
    });

    permanentScanStopBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: scannerModeSelect?.value === "login" ? "loginScanEnd" : "dataScanEnd"
        });
    });

    beaconsStartBtn?.addEventListener('click', () => {
        const uuid = String(beaconUuidInput?.value || "").trim();
        const request = { action: "beaconsStart" };
        if (uuid) {
            request.uuid = uuid;
        }
        sendBridgeMessage(request);
    });

    beaconsStopBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "beaconsStop" });
    });

    beaconAdvertiseStartBtn?.addEventListener('click', () => {
        const uuid = String(beaconAdvertiseUuidInput?.value || "").trim();
        const major = Number.parseInt(beaconAdvertiseMajorInput?.value || "1", 10);
        const minor = Number.parseInt(beaconAdvertiseMinorInput?.value || "1", 10);
        const request = {
            action: "beaconAdvertiseStart",
            major: Number.isFinite(major) ? major : 1,
            minor: Number.isFinite(minor) ? minor : 1
        };
        if (uuid) {
            request.uuid = uuid;
        }
        sendBridgeMessage(request);
    });

    beaconAdvertiseStopBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "beaconAdvertiseStop" });
    });

    orientationSetBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "screenOrientationSet",
            mode: orientationSelect?.value || "unlocked"
        });
    });

    deviceInfoBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "deviceInfoGet" });
    });

    wifiStatusBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "wifiStatusGet" });
    });

    wifiConfigureBtn?.addEventListener('click', () => {
        const ssid = String(wifiSsidInput?.value || "").trim();
        if (!ssid) {
            displayError("Bitte eine WLAN-SSID eingeben.");
            return;
        }

        sendBridgeMessage({
            action: "wifiConfigure",
            ssid,
            passphrase: String(wifiPasswordInput?.value || ""),
            joinOnce: false
        });
    });

    configPairingShowBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "configPairingShow" });
    });

    configPairingStopBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "configPairingStop" });
    });

    configPairingScanBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "continuousScanStart",
            purpose: "configPairing",
            camera: "front",
            types: ["qr"],
            repeatDelaySeconds: 1,
            showFlipButton: true,
            previewRect: {
                top: 0.18,
                left: 0.10,
                width: 0.80,
                height: 0.36
            }
        });
    });

    configPairingConnectBtn?.addEventListener('click', () => {
        const payload = pairingPayloadFromInput();
        if (!payload) {
            displayError("Bitte zuerst einen Pairing-QR scannen oder das Payload einfügen.");
            return;
        }
        updateConfigFormFromPairingPayload(payload);
        sendBridgeMessage({
            action: "configPairingConnect",
            payload
        });
    });

    configPairingDisconnectBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "configPairingDisconnect" });
    });

    localSettingsGetBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "settingsGet" });
    });

    localSettingsSetBtn?.addEventListener('click', () => {
        const token = configSecurityToken();
        if (!token) {
            displayError("Bitte den Security Token für lokale Settings eingeben.");
            return;
        }
        sendBridgeMessage({
            action: "settingsSet",
            token,
            settings: configSettingsFromForm()
        });
    });

    configStatusBtn?.addEventListener('click', () => {
        sendConfigPairingCommand("statusGet");
    });

    configSettingsGetBtn?.addEventListener('click', () => {
        sendConfigPairingCommand("settingsGet");
    });

    configSettingsSetBtn?.addEventListener('click', () => {
        sendConfigPairingCommand("settingsSet", {
            settings: configSettingsFromForm()
        });
    });

    configWifiConfigureBtn?.addEventListener('click', () => {
        const ssid = String(configWifiSsidInput?.value || "").trim();
        if (!ssid) {
            displayError("Bitte Ziel-WLAN-SSID eingeben.");
            return;
        }
        sendConfigPairingCommand("wifiConfigure", {
            ssid,
            passphrase: String(configWifiPasswordInput?.value || ""),
            joinOnce: false
        });
    });

    configReloadBtn?.addEventListener('click', () => {
        sendConfigPairingCommand("reload");
    });

    screenshotBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "screenshotGet",
            maxWidth: 720,
            quality: 75
        });
    });

    geoGetBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "geoLocationGet" });
    });

    geoStartBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "geoLocationStart",
            intervalMs: 3000,
            minDistanceMeters: 0
        });
    });

    geoStopBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "geoLocationStop" });
    });

    soundPlayBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "soundPlay",
            frequencyHz: 880,
            durationMs: 260,
            volume: 0.85
        });
    });

    notificationPermissionBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "notificationPermissionRequest" });
    });

    notificationShowBtn?.addEventListener('click', () => {
        sendBridgeMessage(createNotificationRequest("notificationShow"));
    });

    notificationScheduleBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            ...createNotificationRequest("notificationSchedule", "demo-local-scheduled"),
            seconds: 10
        });
    });

    notificationCancelBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "notificationCancelAll" });
    });

    idleStartBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "idleTimerStart",
            timeoutSeconds: numericInputValue(idleTimeoutInput, 30),
            intervalSeconds: numericInputValue(idleIntervalInput, 1)
        });
    });

    idleResetBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "idleTimerReset" });
    });

    idleStopBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "idleTimerStop" });
    });

    sensorCapabilitiesBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "sensorCapabilitiesGet" });
    });

    sensorStartBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "sensorStreamStart",
            intervalMs: 500,
            types: ["accelerometer", "gyroscope", "magnetometer", "light", "pressure", "proximity"]
        });
    });

    sensorStopBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "sensorStreamStop" });
    });

    screenStreamStartBtn?.addEventListener('click', () => {
        const targetUrl = String(screenStreamTargetInput?.value || "").trim();
        if (!targetUrl) {
            displayError("Bitte eine WebSocket-Zieladresse für den Screenstream eingeben.");
            return;
        }

        sendBridgeMessage({
            action: "screenStreamStart",
            transport: "websocket",
            targetUrl,
            format: "jpeg",
            fps: numericInputValue(screenStreamFpsInput, 2),
            maxWidth: numericInputValue(screenStreamWidthInput, 720),
            quality: 65
        });
    });

    screenStreamStopBtn?.addEventListener('click', () => {
        sendBridgeMessage({ action: "screenStreamStop" });
    });

    storageSetBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "storageSet",
            namespace: nativeStorageNamespace(),
            key: nativeStorageKey(),
            value: parseJsonish(storageValueInput?.value || "")
        });
    });

    storageGetBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "storageGet",
            namespace: nativeStorageNamespace(),
            key: nativeStorageKey()
        });
    });

    storageRemoveBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "storageRemove",
            namespace: nativeStorageNamespace(),
            key: nativeStorageKey()
        });
    });

    storageClearBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "storageClear",
            namespace: nativeStorageNamespace()
        });
    });

    fileWriteBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "filesystemWrite",
            directory: nativeFileDirectory(),
            path: nativeFilePath(),
            data: String(fileDataInput?.value || ""),
            encoding: "utf8"
        });
    });

    fileReadBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "filesystemRead",
            directory: nativeFileDirectory(),
            path: nativeFilePath(),
            encoding: "utf8"
        });
    });

    fileListBtn?.addEventListener('click', () => {
        const path = nativeFilePath();
        sendBridgeMessage({
            action: "filesystemList",
            directory: nativeFileDirectory(),
            path: path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : ""
        });
    });

    fileDeleteBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "filesystemDelete",
            directory: nativeFileDirectory(),
            path: nativeFilePath()
        });
    });

    sqliteInitBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "sqliteExecute",
            database: nativeSQLiteDatabase(),
            sql: "CREATE TABLE IF NOT EXISTS demo_store (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)"
        });
    });

    sqliteUpsertBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "sqliteExecute",
            database: nativeSQLiteDatabase(),
            sql: "INSERT OR REPLACE INTO demo_store (key, value, updated_at) VALUES (?, ?, ?)",
            args: [nativeSQLiteKey(), String(sqliteValueInput?.value || ""), new Date().toISOString()]
        });
    });

    sqliteListBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "sqliteExecute",
            database: nativeSQLiteDatabase(),
            sql: "SELECT key, value, updated_at FROM demo_store ORDER BY key"
        });
    });

    sqliteDeleteDbBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "sqliteDeleteDatabase",
            database: nativeSQLiteDatabase()
        });
    });

    kioskReloadEnableBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "kioskReloadControlSet",
            enabled: true,
            opacity: numericInputRange(kioskOpacityInput, 0.1, 0.02, 1),
            longPressSeconds: numericInputRange(kioskLongPressInput, 2, 0.5, 10)
        });
    });

    kioskReloadDisableBtn?.addEventListener('click', () => {
        sendBridgeMessage({
            action: "kioskReloadControlSet",
            enabled: false
        });
    });

    printEpsonHelloBtn?.addEventListener('click', () => {
        const request = createPrinterHelloRequest();
        if (request) {
            sendBridgeMessage(request);
        }
    });

    discoverPrintersBtn?.addEventListener('click', () => {
        sendBridgeMessage(createPrinterDiscoverRequest());
    });

    printerSelect?.addEventListener('change', selectDiscoveredPrinter);

    clearResultBtn.addEventListener('click', () => {
        clearResultArea();
        clearEventLog();
    });
    removeBackgroundCheckbox?.addEventListener('change', updatePhotoOptionControls);
    photoBackgroundMode?.addEventListener('change', updatePhotoOptionControls);
    cropTransparentCheckbox?.addEventListener('change', updatePhotoOptionControls);
    portraitRemoveBackgroundCheckbox?.addEventListener('change', updatePhotoOptionControls);
    portraitBackgroundMode?.addEventListener('change', updatePhotoOptionControls);
    portraitCropTransparentCheckbox?.addEventListener('change', updatePhotoOptionControls);
    updatePhotoOptionControls();

    // --- Funktionen ---

    function createPhotoRequest(camera) {
        const shouldRemoveBackground = Boolean(removeBackgroundCheckbox?.checked);
        const background = photoBackgroundMode?.value || "transparent";
        const backgroundColor = normalizeHexColor(photoBackgroundColor?.value || "#ffffff");
        const cropTransparent = Boolean(cropTransparentCheckbox?.checked);
        const outputType = (shouldRemoveBackground && background === "transparent") ? "png" : "jpeg";

        return {
            action: "takePhoto",
            camera,
            outputType,
            removeBackground: shouldRemoveBackground,
            background,
            backgroundColor,
            cropTransparent
        };
    }

    function createPortraitCaptureRequest() {
        const shouldRemoveBackground = Boolean(portraitRemoveBackgroundCheckbox?.checked);
        const background = portraitBackgroundMode?.value || "transparent";
        const backgroundColor = normalizeHexColor(portraitBackgroundColor?.value || "#ffffff");
        const cropTransparent = Boolean(portraitCropTransparentCheckbox?.checked);
        const mirrorOutput = Boolean(portraitMirrorOutputCheckbox?.checked);
        const requestedOutputType = portraitOutputTypeSelect?.value === "jpeg" ? "jpeg" : "png";
        const outputType = (shouldRemoveBackground && background === "transparent") ? "png" : requestedOutputType;

        return {
            action: "portraitCapture",
            camera: portraitCameraSelect?.value === "back" ? "back" : "front",
            requiredFaces: numericInputInt(portraitFacesInput, 1, 1, 8),
            countdownSeconds: numericInputRange(portraitCountdownInput, 3, 0, 15),
            variationCount: numericInputInt(portraitVariationInput, 4, 1, 8),
            captureIntervalMs: numericInputInt(portraitIntervalInput, 200, 50, 2000),
            outputType,
            removeBackground: shouldRemoveBackground,
            background,
            backgroundColor,
            cropTransparent,
            mirrorOutput,
            crop: portraitCropSelect?.value === "none" ? "none" : "squareFaceCentered"
        };
    }

    function normalizeHexColor(hexColor) {
        const raw = String(hexColor || "").trim();
        const normalized = raw.startsWith("#") ? raw : `#${raw}`;
        return /^#[0-9a-fA-F]{6}$/.test(normalized) ? normalized.toUpperCase() : "#FFFFFF";
    }

    function createPrinterHelloRequest() {
        const selectedPrinter = currentSelectedPrinter();
        const host = String(epsonPrinterHost?.value || "").trim();
        if (!selectedPrinter && !host) {
            displayError("Bitte zuerst Drucker suchen oder einen Epson-Druckerhost eingeben.");
            return null;
        }

        const printer = selectedPrinter || {
            id: `epson_epos_xml-${host}-80`,
            kind: "epson_epos_xml",
            label: "Epson ePOS-Print",
            host,
            port: 80
        };
        return {
            action: "printerHelloWorld",
            printer,
            kind: printer.kind || "epson_epos_xml",
            host: printer.host || host,
            port: printer.port || 80,
            devid: "local_printer",
            timeoutMs: 20000,
            title: "Hallo Welt",
            subtitle: "swiftHTMLWebviewApp",
            body: `JS Bridge Test ${new Date().toLocaleString()}`
        };
    }

    function createPrinterDiscoverRequest() {
        return {
            action: "printerDiscover",
            timeoutMs: 700,
            httpTimeoutMs: 1000,
            concurrency: 96,
            scanEpson: true,
            scanEscpos: true
        };
    }

    function createNotificationRequest(action, id = "demo-local-now") {
        return {
            action,
            id,
            title: "swiftHTMLWebviewApp",
            body: `Lokale Notification ${new Date().toLocaleTimeString()}`,
            sound: true,
            data: {
                source: "demo",
                id
            }
        };
    }

    function nativeStorageNamespace() {
        return String(storageNamespaceInput?.value || "demo").trim() || "demo";
    }

    function nativeStorageKey() {
        return String(storageKeyInput?.value || "station").trim() || "station";
    }

    function nativeFileDirectory() {
        return fileDirectorySelect?.value || "data";
    }

    function nativeFilePath() {
        return String(filePathInput?.value || "demo/state.json").trim() || "demo/state.json";
    }

    function nativeSQLiteDatabase() {
        return String(sqliteDatabaseInput?.value || "demo.sqlite").trim() || "demo.sqlite";
    }

    function nativeSQLiteKey() {
        return String(sqliteKeyInput?.value || "station").trim() || "station";
    }

    function parseJsonish(value) {
        const raw = String(value || "").trim();
        if (!raw) {
            return "";
        }
        try {
            return JSON.parse(raw);
        } catch (error) {
            return raw;
        }
    }

    function createPermanentScanStartRequest() {
        const mode = scannerModeSelect?.value === "login" ? "login" : "data";
        return {
            action: mode === "login" ? "loginScanStart" : "dataScanStart",
            mode,
            camera: scannerCameraSelect?.value === "front" ? "front" : "back",
            repeatDelaySeconds: 1.2,
            types: ["qr", "ean13", "ean8", "code128", "datamatrix"],
            previewRect: createScannerPreviewRect()
        };
    }

    function createScannerPreviewRect() {
        return {
            top: numericInputPercent(scannerTopInput, 18),
            left: numericInputPercent(scannerLeftInput, 10),
            width: numericInputPercent(scannerWidthInput, 80),
            height: numericInputPercent(scannerHeightInput, 36)
        };
    }

    function numericInputPercent(input, fallback) {
        const raw = Number(input?.value);
        const value = Number.isFinite(raw) ? raw : fallback;
        return Math.max(0, Math.min(100, value)) / 100;
    }

    function numericInputValue(input, fallback) {
        const raw = Number(input?.value);
        return Number.isFinite(raw) ? raw : fallback;
    }

    function numericInputRange(input, fallback, min, max) {
        const value = numericInputValue(input, fallback);
        return Math.max(min, Math.min(max, value));
    }

    function numericInputInt(input, fallback, min, max) {
        return Math.round(numericInputRange(input, fallback, min, max));
    }

    function pairingPayloadFromInput() {
        return String(configPairingPayloadInput?.value || "").trim();
    }

    function identityFromPairingPayload(payload) {
        try {
            const url = new URL(String(payload || ""));
            if (url.protocol !== "swifthtml-config:" || url.hostname !== "pair") {
                return null;
            }
            const params = url.searchParams;
            return {
                appUUID: params.get("appUUID") || params.get("appUuid") || params.get("app_uuid") || "",
                deviceName: params.get("deviceName") || params.get("device_name") || "",
                deviceUUID: params.get("deviceUUID") || params.get("deviceUuid") || params.get("device_uuid") || "",
                deviceLocation: params.get("deviceLocation") || params.get("device_location") || ""
            };
        } catch (error) {
            return null;
        }
    }

    function updateConfigFormFromPairingPayload(payload) {
        const identity = identityFromPairingPayload(payload);
        if (identity) {
            updateConfigFormFromSettings(identity);
        }
    }

    function configSecurityToken() {
        return String(configSecurityTokenInput?.value || "").trim();
    }

    function configSettingsFromForm() {
        const settings = {
            serverURL: String(configServerUrlInput?.value || "").trim() || "local",
            highAvailabilityEnabled: Boolean(configHaEnabledInput?.checked),
            highAvailabilityTimeoutSeconds: Math.max(1, numericInputValue(configHaTimeoutInput, 5)),
            highAvailabilityURL2: String(configUrl2Input?.value || "").trim(),
            highAvailabilityURL3: String(configUrl3Input?.value || "").trim(),
            highAvailabilityURL4: String(configUrl4Input?.value || "").trim(),
            beaconUUID: String(configBeaconUuidInput?.value || "").trim(),
            deviceName: String(configDeviceNameInput?.value || "").trim(),
            deviceUUID: String(configDeviceUuidInput?.value || "").trim(),
            deviceLocation: String(configDeviceLocationInput?.value || "").trim()
        };
        const newSecurityToken = String(configNewSecurityTokenInput?.value || "").trim();
        if (newSecurityToken) {
            settings.newSecurityToken = newSecurityToken;
        }
        return settings;
    }

    function sendConfigPairingCommand(command, extra = {}) {
        const token = configSecurityToken();
        if ((command === "settingsSet" || command === "wifiConfigure" || command === "reload") && !token) {
            displayError("Bitte den Security Token für schreibende Config-Kommandos eingeben.");
            return;
        }

        sendBridgeMessage({
            action: "configPairingSend",
            command,
            token,
            ...extra
        });
    }

    function updateConfigFormFromSettings(settings) {
        if (!settings || typeof settings !== "object") {
            return;
        }
        if (configServerUrlInput && typeof settings.serverURL === "string") {
            configServerUrlInput.value = settings.serverURL;
        }
        if (configAppUuidOutput && typeof settings.appUUID === "string") {
            configAppUuidOutput.value = settings.appUUID;
        }
        if (configDeviceNameInput && typeof settings.deviceName === "string") {
            configDeviceNameInput.value = settings.deviceName;
        }
        if (configDeviceUuidInput && typeof settings.deviceUUID === "string") {
            configDeviceUuidInput.value = settings.deviceUUID;
        }
        if (configDeviceLocationInput && typeof settings.deviceLocation === "string") {
            configDeviceLocationInput.value = settings.deviceLocation;
        }
        if (configHaEnabledInput && typeof settings.highAvailabilityEnabled === "boolean") {
            configHaEnabledInput.checked = settings.highAvailabilityEnabled;
        }
        if (configHaTimeoutInput && settings.highAvailabilityTimeoutSeconds != null) {
            configHaTimeoutInput.value = String(settings.highAvailabilityTimeoutSeconds);
        }
        if (configUrl2Input && typeof settings.highAvailabilityURL2 === "string") {
            configUrl2Input.value = settings.highAvailabilityURL2;
        }
        if (configUrl3Input && typeof settings.highAvailabilityURL3 === "string") {
            configUrl3Input.value = settings.highAvailabilityURL3;
        }
        if (configUrl4Input && typeof settings.highAvailabilityURL4 === "string") {
            configUrl4Input.value = settings.highAvailabilityURL4;
        }
        if (configBeaconUuidInput && typeof settings.beaconUUID === "string") {
            configBeaconUuidInput.value = settings.beaconUUID;
        }
    }

    function selectDiscoveredPrinter() {
        const selected = currentSelectedPrinter();
        if (selected?.host && epsonPrinterHost) {
            epsonPrinterHost.value = selected.host;
        }
    }

    function currentSelectedPrinter() {
        const index = Number(printerSelect?.value);
        if (!Number.isInteger(index) || index < 0) {
            return null;
        }
        return discoveredPrinters[index] || null;
    }

    function updatePhotoOptionControls() {
        if (photoBackgroundMode && photoBackgroundColor && cropTransparentCheckbox) {
            const removeChecked = Boolean(removeBackgroundCheckbox?.checked);
            const backgroundMode = photoBackgroundMode.value || "transparent";
            const cropEnabled = removeChecked && backgroundMode === "transparent";

            photoBackgroundMode.disabled = !removeChecked;
            photoBackgroundColor.disabled = !removeChecked || backgroundMode !== "color";
            cropTransparentCheckbox.disabled = !cropEnabled;
            if (!cropEnabled && !removeChecked) {
                cropTransparentCheckbox.checked = false;
            }
        }

        if (portraitBackgroundMode && portraitBackgroundColor && portraitCropTransparentCheckbox) {
            const removeChecked = Boolean(portraitRemoveBackgroundCheckbox?.checked);
            const backgroundMode = portraitBackgroundMode.value || "transparent";
            const cropEnabled = removeChecked && backgroundMode === "transparent";

            portraitBackgroundMode.disabled = !removeChecked;
            portraitBackgroundColor.disabled = !removeChecked || backgroundMode !== "color";
            portraitCropTransparentCheckbox.disabled = !cropEnabled;
            if (!cropEnabled && !removeChecked) {
                portraitCropTransparentCheckbox.checked = false;
            }
        }
    }

    // Sendet eine Nachricht an die Native Bridge
    function sendBridgeMessage(message) {
        if (window.webkit?.messageHandlers?.swiftBridge) {
            logDebug("Sending native bridge message:", message);
            const isConfettiAction = message.action === "launchConfetti";
            const isCommandAction = commandActions.has(message.action);
            if (!isConfettiAction && !isCommandAction) {
                showLoadingStatus(`Aktion '${message.action}' wird ausgeführt...`);
                clearResultArea(false); // Ergebnisbereich leeren, aber Placeholder nicht zeigen
            }
            window.webkit.messageHandlers.swiftBridge.postMessage(message);
        } else {
            console.error("Native bridge (window.webkit.messageHandlers.swiftBridge) ist nicht verfügbar.");
            displayError("Fehler: Die Verbindung zur nativen App ist nicht verfügbar.");
        }
    }

    // Globale Funktion, die von Native aufgerufen wird
    window.handleNativeResult = function(result) {
        logDebug("Received native bridge result:", result);
        if (liveEventActions.has(result.action)) {
            appendLiveEvent(result);
            return;
        }

        if (result.action !== "launchConfetti") {
            hideLoadingStatus(); // Ladeanzeige ausblenden
        }

        if (result.action !== "launchConfetti" && !commandActions.has(result.action)) {
            clearResultArea(false); // Ergebnisbereich leeren
        }

        if (result.error
            && result.action !== "printerEpsonHelloWorld"
            && result.action !== "printerHelloWorld"
            && result.action !== "printerDiscover"
            && !commandActions.has(result.action)) {
            displayError(result.error);
            return;
        }

        // Erfolgreiches Ergebnis verarbeiten
        switch (result.action) {
            case "scanDocument":
                displayDocumentResult(result);
                break;
            case "takePhoto":
            case "portraitCapture":
                displayPhotoResult(result);
                break;
            case "launchConfetti":
                handleConfettiResult(result);
                break;
            case "scanBarcode":
                displayBarcodeResult(result);
                break;
            case "nfcTagRead":
                displayNfcTagResult(result);
                break;
            case "screenshotGet":
                displayScreenshotResult(result);
                break;
            case "printerEpsonHelloWorld":
            case "printerHelloWorld":
                displayPrinterResult(result);
                break;
            case "printerDiscover":
                displayPrinterDiscoveryResult(result);
                break;
            case "configPairingResponse":
                if (result.settings) {
                    updateConfigFormFromSettings(result.settings);
                }
                displayCommandResult(result);
                break;
            case "continuousScanStart":
            case "continuousScanStop":
            case "dataScanStart":
            case "dataScanEnd":
            case "loginScanStart":
            case "loginScanEnd":
            case "previewBoxLocationUpdate":
            case "beaconsStart":
            case "beaconsStop":
            case "beaconAdvertiseStart":
            case "beaconAdvertiseStop":
            case "settingsGet":
            case "settingsSet":
            case "storageGet":
            case "storageSet":
            case "storageRemove":
            case "storageClear":
            case "filesystemWrite":
            case "filesystemRead":
            case "filesystemList":
            case "filesystemDelete":
            case "sqliteExecute":
            case "sqliteDeleteDatabase":
            case "kioskReloadControlSet":
                if (result.settings) {
                    updateConfigFormFromSettings(result.settings);
                }
                displayCommandResult(result);
                break;
            case "screenOrientationSet":
            case "wifiConfigure":
            case "geoLocationStart":
            case "geoLocationStop":
            case "soundPlay":
            case "notificationPermissionGet":
            case "notificationPermissionRequest":
            case "notificationShow":
            case "notificationSchedule":
            case "notificationCancel":
            case "notificationCancelAll":
            case "notificationList":
            case "idleTimerStart":
            case "idleTimerStop":
            case "idleTimerReset":
            case "sensorStreamStart":
            case "sensorStreamStop":
            case "screenStreamStart":
            case "screenStreamStop":
            case "configPairingStop":
            case "configPairingDisconnect":
            case "configPairingSend":
                displayCommandResult(result);
                break;
            case "configPairingShow":
                if (result.targetIdentity) {
                    updateConfigFormFromSettings(result.targetIdentity);
                }
                if (result.payload) {
                    updateConfigFormFromPairingPayload(result.payload);
                }
                displayCommandResult(result);
                break;
            case "configPairingConnect":
                if (result.targetIdentity) {
                    updateConfigFormFromSettings(result.targetIdentity);
                }
                displayCommandResult(result);
                break;
            default:
                logDebug("Received result for unknown action:", result.action);
                displayFallbackResult(result);
        }
    };

    // --- Anzeige-Funktionen ---

    function displayDocumentResult(result) {
        if (result.format === 'pdf' && result.pdfData) {
            // Speichere die PDF-Daten im Session Storage
            sessionStorage.setItem("pdfData", result.pdfData);
            
            // Erzeuge einen Link, der die pdf.html (den PDF-Viewer) öffnet
            const link = document.createElement("a");
            link.href = "./pdf.html"; // Stelle sicher, dass der Pfad stimmt!
            link.textContent = "PDF ansehen";
            //link.target = "_blank"; // Öffnet in einem neuen Tab/Fenster
            
            // Füge eine Überschrift und den Link in den Ergebnisbereich ein
            resultArea.appendChild(createResultHeader(`Dokument (${result.pages} Seiten) als PDF:`));
            resultArea.appendChild(link);
        } else if (result.images && result.images.length > 0) {
            // Bestehende Logik für Bilddarstellung
            resultArea.appendChild(createResultHeader(`Dokument (${result.pages} Seiten) als ${result.format?.toUpperCase()}:`));
            result.images.forEach((imgDataUrl, index) => {
                const img = document.createElement('img');
                img.src = imgDataUrl;
                img.alt = `Gescannte Seite ${index + 1}`;
                resultArea.appendChild(img);
            });
        } else {
            displayError("Keine gültigen PDF- oder Bilddaten empfangen.");
        }
    
        // OCR-Text anzeigen, falls vorhanden
        if (result.text) {
            resultArea.appendChild(createResultHeader("Erkannter Text (OCR):"));
            const pre = document.createElement('pre');
            pre.textContent = result.text;
            resultArea.appendChild(pre);
        } else if (result.ocr === true) {
            resultArea.appendChild(createResultHeader("Erkannter Text (OCR):"));
            const p = document.createElement('p');
            p.textContent = "(Kein Text erkannt)";
            resultArea.appendChild(p);
        }
    }

    function displayPhotoResult(result) {
        if (result.imageData) {
             resultArea.appendChild(createResultHeader(`Foto (${result.format?.toUpperCase()}):`));

            if (result.backgroundRemoved) {
                const backgroundInfo = document.createElement('p');
                if (result.background === "color") {
                    backgroundInfo.textContent = `Hintergrund entfernt (${result.backgroundColor || "#FFFFFF"})`;
                } else {
                    const croppedSuffix = result.cropped ? ", zugeschnitten" : "";
                    backgroundInfo.textContent = `Hintergrund entfernt (transparent${croppedSuffix})`;
                }
                resultArea.appendChild(backgroundInfo);
            }

            const img = document.createElement('img');
            img.src = result.imageData;
            img.alt = 'Aufgenommenes Foto';
            resultArea.appendChild(img);
        } else {
             displayError("Keine gültigen Bilddaten für das Foto empfangen.");
        }
    }

    function displayScreenshotResult(result) {
        if (!result.imageData) {
            displayFallbackResult(result);
            return;
        }

        resultArea.appendChild(createResultHeader(`Screenshot (${result.width || "?"} × ${result.height || "?"})`));
        const img = document.createElement('img');
        img.src = result.imageData;
        img.alt = 'Nativer Screenshot';
        resultArea.appendChild(img);

        const pre = document.createElement('pre');
        const copy = { ...result, imageData: `<${String(result.imageData).length} Zeichen>` };
        pre.textContent = JSON.stringify(copy, null, 2);
        resultArea.appendChild(pre);
    }

    function handleConfettiResult(result) {
        if (confettiBtn) {
            confettiBtn.textContent = confettiMoreLabel;
        }

        if (placeholderText && placeholderText.parentElement === resultArea) {
            placeholderText.remove();
        }

        const info = document.createElement('p');
        if (typeof result?.burstCount === 'number') {
            info.textContent = `Konfetti gestartet (Salve ${result.burstCount}).`;
        } else {
            info.textContent = "Konfetti gestartet.";
        }
        resultArea.appendChild(info);
    }

    function displayBarcodeResult(result) {
        if (result.code === "configChanged" && result.settings) {
            updateConfigFormFromSettings(result.settings);
        }
        if (result.code) {
            if (String(result.code).startsWith("swifthtml-config://pair") && configPairingPayloadInput) {
                configPairingPayloadInput.value = result.code;
                updateConfigFormFromPairingPayload(result.code);
            }
            resultArea.appendChild(createResultHeader("Barcode erkannt:"));
            const pre = document.createElement('pre');
            pre.textContent = `Format: ${result.format || 'Unbekannt'}\nWert:   ${result.code}`;
            resultArea.appendChild(pre);
             // Optional: Wenn es eine URL ist, einen Link anbieten
             try {
                 const url = new URL(result.code);
                 if (url.protocol === "http:" || url.protocol === "https:") {
                     const link = document.createElement('a');
                     link.href = result.code;
                     link.textContent = "Link öffnen";
                     link.target = "_blank"; // In neuem Tab öffnen (funktioniert in WKWebView ggf. nicht wie erwartet)
                     link.style.display = 'block';
                     link.style.marginTop = '10px';
                     resultArea.appendChild(link);
                 }
             } catch (_) {
                 // Ist keine gültige URL, ignoriere es
             }

        } else {
             displayError("Kein Barcode erkannt oder Scan abgebrochen.");
        }
    }

    function displayNfcTagResult(result) {
        if (!result.success) {
            displayFallbackResult(result);
            return;
        }

        const tag = result.tag || {};
        const ndef = result.ndef || {};
        const records = Array.isArray(ndef.records) ? ndef.records : [];

        resultArea.appendChild(createResultHeader("NFC Tag gelesen:"));

        const summary = document.createElement('p');
        summary.className = 'success';
        const techs = Array.isArray(tag.technologies) ? tag.technologies.join(', ') : (tag.type || 'unbekannt');
        summary.textContent = `Tag ${tag.identifierHex || tag.identifierBase64 || ''} ${techs ? `(${techs})` : ''}`.trim();
        resultArea.appendChild(summary);

        if (records.length > 0) {
            const list = document.createElement('ul');
            records.forEach((record) => {
                const item = document.createElement('li');
                const value = record.text || record.uri || record.mimeType || record.payloadHex || record.payloadBase64 || '';
                item.textContent = `${record.typeNameFormat || 'record'}${record.type ? `/${record.type}` : ''}: ${value}`;
                list.appendChild(item);
            });
            resultArea.appendChild(list);
        } else {
            const message = document.createElement('p');
            message.textContent = ndef.available === false
                ? "Kein NDEF-Inhalt auf diesem Tag verfügbar."
                : "Keine NDEF-Records gefunden.";
            resultArea.appendChild(message);
        }

        const pre = document.createElement('pre');
        pre.textContent = JSON.stringify(result, null, 2);
        resultArea.appendChild(pre);
    }

    function displayCommandResult(result) {
        resultArea.appendChild(createResultHeader("Bridge Kommando:"));

        const message = document.createElement('p');
        message.className = result.success ? 'success' : 'error';
        message.textContent = result.success
            ? `${result.action} OK`
            : (result.error || `${result.action} fehlgeschlagen.`);
        resultArea.appendChild(message);

        const pre = document.createElement('pre');
        pre.textContent = JSON.stringify(result, null, 2);
        resultArea.appendChild(pre);
    }

    function appendLiveEvent(result) {
        if (!eventLog) {
            return;
        }
        const muted = eventLog.querySelector('.muted');
        if (muted) {
            muted.remove();
        }

        const entry = document.createElement('div');
        entry.className = 'event-entry';

        const title = document.createElement('strong');
        if (result.action === "beacons") {
            title.textContent = `beacons: ${result.count ?? 0}`;
        } else if (result.action === "idleTick" || result.action === "idleTimeout") {
            title.textContent = `${result.action}: ${Number(result.idleSeconds || 0).toFixed(1)}s`;
        } else if (result.action === "screenStreamStats") {
            title.textContent = `screenStream: ${formatBytes(result.bytes || 0)} / ${result.frames || 0} Frames`;
        } else if (result.action === "sensorData") {
            const count = Array.isArray(result.sensors) ? result.sensors.length : 1;
            title.textContent = `sensorData: ${count}`;
        } else if (result.action === "geoLocation") {
            const location = result.location || {};
            title.textContent = `geoLocation: ${location.latitude ?? "?"}, ${location.longitude ?? "?"}`;
        } else {
            title.textContent = `${result.action}: ${result.format || ''} ${result.code || ''}`.trim();
        }
        entry.appendChild(title);

        const pre = document.createElement('pre');
        pre.textContent = JSON.stringify(result, null, 2);
        entry.appendChild(pre);

        eventLog.prepend(entry);
        while (eventLog.children.length > 20) {
            eventLog.removeChild(eventLog.lastElementChild);
        }
    }

    function formatBytes(bytes) {
        const value = Number(bytes || 0);
        if (value >= 1024 * 1024) {
            return `${(value / (1024 * 1024)).toFixed(2)} MB`;
        }
        if (value >= 1024) {
            return `${(value / 1024).toFixed(1)} KB`;
        }
        return `${value} B`;
    }

    function displayPrinterResult(result) {
        resultArea.appendChild(createResultHeader("Druckauftrag:"));

        const message = document.createElement('p');
        message.className = result.success ? 'success' : 'error';
        if (result.success) {
            const label = result.printerLabel || result.host || 'Drucker';
            const mode = result.printerKind || result.kind || result.devid || 'local_printer';
            message.textContent = `Gedruckt auf ${label} (${mode}).`;
        } else {
            message.textContent = result.error || result.message || "Druckauftrag fehlgeschlagen.";
        }
        resultArea.appendChild(message);

        const pre = document.createElement('pre');
        pre.textContent = JSON.stringify(result, null, 2);
        resultArea.appendChild(pre);
    }

    function displayPrinterDiscoveryResult(result) {
        const printers = Array.isArray(result.printers) ? result.printers : [];
        discoveredPrinters = printers;
        populatePrinterSelect(printers);

        resultArea.appendChild(createResultHeader("Druckersuche:"));

        const message = document.createElement('p');
        message.className = printers.length > 0 ? 'success' : 'error';
        message.textContent = printers.length > 0
            ? `${printers.length} Druckerziel(e) gefunden.`
            : (result.message || result.error || "Keine Drucker gefunden.");
        resultArea.appendChild(message);

        if (printers.length > 0) {
            const list = document.createElement('ul');
            list.className = 'printer-list';
            printers.forEach((printer) => {
                const item = document.createElement('li');
                item.textContent = printerDisplayName(printer);
                list.appendChild(item);
            });
            resultArea.appendChild(list);
        }

        const pre = document.createElement('pre');
        pre.textContent = JSON.stringify(result, null, 2);
        resultArea.appendChild(pre);
    }

    function populatePrinterSelect(printers) {
        if (!printerSelect) {
            return;
        }

        printerSelect.innerHTML = "";
        if (printers.length === 0) {
            const option = document.createElement('option');
            option.value = "";
            option.textContent = "Keine Drucker gefunden";
            printerSelect.appendChild(option);
            printerSelect.disabled = true;
            return;
        }

        printers.forEach((printer, index) => {
            const option = document.createElement('option');
            option.value = String(index);
            option.textContent = printerDisplayName(printer);
            printerSelect.appendChild(option);
        });
        printerSelect.disabled = false;
        printerSelect.selectedIndex = 0;
        selectDiscoveredPrinter();
    }

    function printerDisplayName(printer) {
        const kind = printerKindLabel(printer?.kind);
        const target = printer?.local ? "lokal" : [printer?.host, printer?.port].filter(Boolean).join(":");
        const confidence = printer?.confidence ? `, ${printer.confidence}` : "";
        return `${printer?.label || kind} (${kind}${target ? `, ${target}` : ""}${confidence})`;
    }

    function printerKindLabel(kind) {
        switch (kind) {
            case "epson_epos_xml":
                return "Epson XML";
            case "escpos_raw":
                return "ESC/POS";
            case "sunmi_internal":
                return "Sunmi intern";
            default:
                return kind || "Drucker";
        }
    }

     function displayFallbackResult(result) {
         resultArea.appendChild(createResultHeader("Unbekanntes Ergebnis:"));
         const pre = document.createElement('pre');
         // Zeige das rohe JSON-Ergebnis formatiert an
         pre.textContent = JSON.stringify(result, null, 2); // 2 Leerzeichen für Einrückung
         resultArea.appendChild(pre);
     }

    function displayError(errorMessage) {
        clearResultArea(false); // Vorherigen Inhalt löschen
        const p = document.createElement('p');
        p.className = 'error'; // CSS-Klasse für Fehlermarkierung
        p.textContent = `Fehler: ${errorMessage}`;
        resultArea.appendChild(p);
        hideLoadingStatus(); // Sicherstellen, dass Ladeanzeige weg ist
    }

    function logDebug(...args) {
        if (debugBridgeMessages) {
            console.debug(...args);
        }
    }

     function createResultHeader(text) {
         const h3 = document.createElement('h3');
         h3.textContent = text;
         h3.style.marginTop = '15px';
         h3.style.marginBottom = '5px';
         h3.style.fontSize = '1.1em';
         h3.style.borderBottom = '1px solid #ddd';
         h3.style.paddingBottom = '5px';
         return h3;
     }

    function clearResultArea(showPlaceholder = true) {
        resultArea.innerHTML = ''; // Leert den Inhaltsbereich
        if (showPlaceholder && placeholderText) {
            resultArea.appendChild(placeholderText); // Fügt den Platzhalter wieder hinzu
            placeholderText.style.display = 'block';
        } else if (placeholderText) {
             placeholderText.style.display = 'none'; // Versteckt den Platzhalter
        }
    }

    function clearEventLog() {
        if (!eventLog) {
            return;
        }
        eventLog.innerHTML = '<p class="muted">Noch keine Scanner- oder Beacon-Events.</p>';
    }

    function showLoadingStatus(message) {
        if (statusArea) {
            statusArea.querySelector('p').textContent = message || 'Aktion wird ausgeführt...';
            statusArea.style.display = 'flex'; // Zeige den Statusbereich
        }
        // Deaktiviere Buttons während der Aktion
        disableButtons(true);
    }

    function hideLoadingStatus() {
        if (statusArea) {
            statusArea.style.display = 'none'; // Verstecke den Statusbereich
        }
         // Aktiviere Buttons wieder
         disableButtons(false);
    }

     function disableButtons(disabled) {
         const buttons = document.querySelectorAll('.controls button');
         buttons.forEach(button => button.disabled = disabled);

         if (removeBackgroundCheckbox) {
             removeBackgroundCheckbox.disabled = disabled;
         }

         if (photoBackgroundMode && photoBackgroundColor && cropTransparentCheckbox) {
             const removeChecked = Boolean(removeBackgroundCheckbox?.checked);
             const isColorMode = (photoBackgroundMode.value || "transparent") === "color";
             const cropEnabled = removeChecked && !isColorMode;
             photoBackgroundMode.disabled = disabled || !removeChecked;
             photoBackgroundColor.disabled = disabled || !removeChecked || !isColorMode;
             cropTransparentCheckbox.disabled = disabled || !cropEnabled;
             if (!cropEnabled && !removeChecked) {
                 cropTransparentCheckbox.checked = false;
             }
         }

         if (portraitRemoveBackgroundCheckbox) {
             portraitRemoveBackgroundCheckbox.disabled = disabled;
         }

         if (portraitMirrorOutputCheckbox) {
             portraitMirrorOutputCheckbox.disabled = disabled;
         }

         if (portraitBackgroundMode && portraitBackgroundColor && portraitCropTransparentCheckbox) {
             const removeChecked = Boolean(portraitRemoveBackgroundCheckbox?.checked);
             const isColorMode = (portraitBackgroundMode.value || "transparent") === "color";
             const cropEnabled = removeChecked && !isColorMode;
             portraitBackgroundMode.disabled = disabled || !removeChecked;
             portraitBackgroundColor.disabled = disabled || !removeChecked || !isColorMode;
             portraitCropTransparentCheckbox.disabled = disabled || !cropEnabled;
             if (!cropEnabled && !removeChecked) {
                 portraitCropTransparentCheckbox.checked = false;
             }
         }

         if (printerSelect) {
             printerSelect.disabled = disabled || discoveredPrinters.length === 0;
         }
     }

    if (confettiBtn) {
        confettiBtn.textContent = confettiInitialLabel;
    }

    // Initiales Leeren beim Laden (optional, falls HTML schon leer ist)
    clearResultArea();

});
