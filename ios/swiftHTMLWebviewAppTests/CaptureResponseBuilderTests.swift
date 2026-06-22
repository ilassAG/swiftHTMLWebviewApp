//
//  CaptureResponseBuilderTests.swift
//  swiftHTMLWebviewAppTests
//

import XCTest
@testable import swiftHTMLWebviewApp

final class CaptureResponseBuilderTests: XCTestCase {
    func testDocumentImageResponseUsesCurrentBridgeFields() {
        let response = DocumentCaptureResponseBuilder.imageResponse(
            action: "scanDocument",
            pageCount: 2,
            text: "recognized text",
            imageDataURLs: ["data:image/png;base64,page1", "data:image/png;base64,page2"],
            format: "png"
        )

        XCTAssertEqual(response["action"] as? String, "scanDocument")
        XCTAssertEqual(response["pages"] as? Int, 2)
        XCTAssertEqual(response["text"] as? String, "recognized text")
        XCTAssertEqual(response["format"] as? String, "png")
        XCTAssertEqual(response["images"] as? [String], ["data:image/png;base64,page1", "data:image/png;base64,page2"])
        XCTAssertNil(response["pdfData"])
    }

    func testDocumentPdfResponseUsesPdfDataField() {
        let response = DocumentCaptureResponseBuilder.pdfResponse(
            action: "scanDocument",
            pageCount: 1,
            text: "",
            pdfDataURL: "data:application/pdf;base64,pdf"
        )

        XCTAssertEqual(response["action"] as? String, "scanDocument")
        XCTAssertEqual(response["pages"] as? Int, 1)
        XCTAssertEqual(response["format"] as? String, "pdf")
        XCTAssertEqual(response["pdfData"] as? String, "data:application/pdf;base64,pdf")
        XCTAssertNil(response["images"])
        XCTAssertNil(response["text"])
    }

    func testPhotoResponseOmitsBackgroundFieldsWhenUnprocessed() {
        let response = PhotoCaptureResponseBuilder.response(
            action: "takePhoto",
            imageDataURL: "data:image/jpeg;base64,photo",
            format: "jpeg",
            backgroundRemoved: false,
            backgroundMode: "transparent",
            cropped: false,
            backgroundColorHex: "#FFFFFF"
        )

        XCTAssertEqual(response["action"] as? String, "takePhoto")
        XCTAssertEqual(response["imageData"] as? String, "data:image/jpeg;base64,photo")
        XCTAssertEqual(response["format"] as? String, "jpeg")
        XCTAssertNil(response["backgroundRemoved"])
        XCTAssertNil(response["background"])
        XCTAssertNil(response["cropped"])
        XCTAssertNil(response["backgroundColor"])
    }

    func testPhotoResponseIncludesBackgroundRemovalMetadata() {
        let response = PhotoCaptureResponseBuilder.response(
            action: "takePhoto",
            imageDataURL: "data:image/png;base64,photo",
            format: "png",
            backgroundRemoved: true,
            backgroundMode: "color",
            cropped: true,
            backgroundColorHex: "#112233"
        )

        XCTAssertEqual(response["action"] as? String, "takePhoto")
        XCTAssertEqual(response["imageData"] as? String, "data:image/png;base64,photo")
        XCTAssertEqual(response["format"] as? String, "png")
        XCTAssertEqual(response["backgroundRemoved"] as? Bool, true)
        XCTAssertEqual(response["background"] as? String, "color")
        XCTAssertEqual(response["cropped"] as? Bool, true)
        XCTAssertEqual(response["backgroundColor"] as? String, "#112233")
    }

    func testPortraitResponseUsesNormalizedEnvelopeAndMetadata() {
        let response = PortraitCaptureResponseBuilder.response(
            action: "portraitCapture",
            imageDataURL: "data:image/png;base64,portrait",
            format: "png",
            selectedIndex: 1,
            variantsCaptured: 4,
            requiredFaces: 1,
            detectedFaces: 1,
            faceCentered: true,
            backgroundRemoved: true,
            backgroundMode: "transparent",
            cropped: true,
            backgroundColorHex: nil
        )

        XCTAssertEqual(response["platform"] as? String, "ios")
        XCTAssertEqual(response["action"] as? String, "portraitCapture")
        XCTAssertEqual(response["success"] as? Bool, true)
        XCTAssertEqual(response["imageData"] as? String, "data:image/png;base64,portrait")
        XCTAssertEqual(response["selectedIndex"] as? Int, 1)
        XCTAssertEqual(response["variantsCaptured"] as? Int, 4)
        XCTAssertEqual(response["requiredFaces"] as? Int, 1)
        XCTAssertEqual(response["detectedFaces"] as? Int, 1)
        XCTAssertEqual(response["faceCentered"] as? Bool, true)
        XCTAssertEqual(response["backgroundRemoved"] as? Bool, true)
        XCTAssertEqual(response["cropped"] as? Bool, true)
    }
}
