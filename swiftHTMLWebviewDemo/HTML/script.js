// Filename: HTML/script.js

document.addEventListener('DOMContentLoaded', () => {
    // --- Elemente holen ---
    const scanDocPdfBtn = document.getElementById('scanDocPdfBtn');
    const scanDocPngBtn = document.getElementById('scanDocPngBtn');
    const takePhotoFrontBtn = document.getElementById('takePhotoFrontBtn');
    const takePhotoBackBtn = document.getElementById('takePhotoBackBtn');
    const scanBarcodeBtn = document.getElementById('scanBarcodeBtn');
    const clearResultBtn = document.getElementById('clearResultBtn');

    const statusArea = document.getElementById('statusArea');
    const resultArea = document.getElementById('resultArea');
    const placeholderText = document.getElementById('placeholderText');

    // --- Event Listeners ---
    scanDocPdfBtn.addEventListener('click', () => {
        const request = {
            action: "scanDocument",
            ocr: true, // Keine OCR für reines PDF
            outputType: "pdf"
        };
        sendMessageToSwift(request);
    });

    scanDocPngBtn.addEventListener('click', () => {
        const request = {
            action: "scanDocument",
            ocr: true, // OCR anfordern
            outputType: "png" // Bilder als PNG
        };
        sendMessageToSwift(request);
    });

    takePhotoFrontBtn.addEventListener('click', () => {
        const request = {
            action: "takePhoto",
            camera: "front",
            outputType: "jpeg" // Standard JPEG
        };
        sendMessageToSwift(request);
    });

    takePhotoBackBtn.addEventListener('click', () => {
        const request = {
            action: "takePhoto",
            camera: "back",
            outputType: "jpeg"
        };
        sendMessageToSwift(request);
    });

    scanBarcodeBtn.addEventListener('click', () => {
        const request = {
            action: "scanBarcode",
            // Kamera wird von Swift entschieden (meist Rückkamera für Barcodes)
            types: ["qr", "ean13", "ean8", "code128", "datamatrix"] // Zu suchende Typen
        };
        sendMessageToSwift(request);
    });

    clearResultBtn.addEventListener('click', clearResultArea);

    // --- Funktionen ---

    // Sendet eine Nachricht an die Swift Bridge
    function sendMessageToSwift(message) {
        if (window.webkit?.messageHandlers?.swiftBridge) {
            console.log("Sending message to Swift:", message);
            showLoadingStatus(`Aktion '${message.action}' wird ausgeführt...`);
            clearResultArea(false); // Ergebnisbereich leeren, aber Placeholder nicht zeigen
            window.webkit.messageHandlers.swiftBridge.postMessage(message);
        } else {
            console.error("Swift Bridge (window.webkit.messageHandlers.swiftBridge) ist nicht verfügbar.");
            displayError("Fehler: Die Verbindung zur nativen App ist nicht verfügbar.");
        }
    }

    // Globale Funktion, die von Swift aufgerufen wird
    window.handleNativeResult = function(result) {
        console.log("Received result from Swift:", result);
        hideLoadingStatus(); // Ladeanzeige ausblenden

        clearResultArea(false); // Ergebnisbereich leeren

        if (result.error) {
            displayError(result.error);
            return;
        }

        // Erfolgreiches Ergebnis verarbeiten
        switch (result.action) {
            case "scanDocument":
                displayDocumentResult(result);
                break;
            case "takePhoto":
                displayPhotoResult(result);
                break;
            case "scanBarcode":
                displayBarcodeResult(result);
                break;
            default:
                console.warn("Received result for unknown action:", result.action);
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
            const img = document.createElement('img');
            img.src = result.imageData;
            img.alt = 'Aufgenommenes Foto';
            resultArea.appendChild(img);
        } else {
             displayError("Keine gültigen Bilddaten für das Foto empfangen.");
        }
    }

    function displayBarcodeResult(result) {
        if (result.code) {
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
     }

    // Initiales Leeren beim Laden (optional, falls HTML schon leer ist)
    clearResultArea();

}); // Ende DOMContentLoaded
