# Secure Document Chain of Trust Plan

This document specifies the native bridge functions required to turn
`swiftHTMLWebviewApp` into a secure customer/employee wrapper for passport,
visa, and Blue Card document handling.

The goal is that a future implementation agent can build the feature without
guessing the API surface, response shape, security expectations, or backend
contract.

## Status

Draft implementation specification.

Do not treat the existing `scanDocument` and `takePhoto` actions as secure
document actions. They currently return cleartext image/PDF data URLs to
JavaScript. The secure document flow below must use new action names and must
not return cleartext document bytes to the WebView.

## Existing Wrapper Context

The wrapper already exposes native capabilities through this shape:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'scanDocument',
  requestId: crypto.randomUUID()
});
```

Native responses are delivered through:

```js
window.handleNativeResult(result);
```

The secure module must keep this pattern:

- Every request should include `requestId`.
- Every response must include `platform`, `action`, `requestId`, and `success`.
- Unsupported secure features must return a structured error or capability
  response, not silently fail.
- Product-specific business policy stays in the backend/web app.
- Native code owns device keys, app attestation, scanner bytes, crypto, and
  secure viewing.

## Security Objective

The platform must support the following product requirement:

An end customer can upload passport/visa scans securely and can later revoke
all future access by the Auftraggeber. Revocation cannot erase documents that
were already viewed, printed, downloaded, photographed, or otherwise copied.
It must, however, prevent all future technical decrypt/view operations through
the platform.

The intended design is envelope encryption:

```text
document bytes
  -> random per-document DEK
  -> AES-256-GCM encrypted document

DEK
  -> encrypted/wrapped into one or more envelopes:
       customer envelope
       KMS/HSM policy envelope
       optional short-lived viewer envelope
```

The Auftraggeber and employees must not receive a permanently usable raw DEK.
They should receive only short-lived server-authorized viewing capability.

## Non-Goals

- Do not implement visa/Blue Card business logic in the wrapper.
- Do not implement custom cryptographic algorithms.
- Do not expose raw Secure Enclave, Keychain, StrongBox, or Keystore handles to
  JavaScript.
- Do not return cleartext passport/visa images or PDFs to JavaScript in secure
  flows.
- Do not claim that revocation can invalidate already exported or printed
  documents.
- Do not rely on the existing `security_token_preference` as a trust anchor.

## Trust Anchors

### iOS

Use platform-provided security primitives:

- App Attest / DeviceCheck for app instance integrity.
- Keychain and Secure Enclave where available for non-exportable private keys.
- `SecAccessControl` / LocalAuthentication for user presence, Face ID, Touch ID,
  or passcode-gated key use.
- CryptoKit/Security framework for standard algorithms only.
- File protection such as complete-until-first-authentication or complete
  protection for temporary encrypted files.

Important platform constraint:

iOS App Attest attests an app-instance key. It does not automatically prove that
every separate Keychain/Secure Enclave key was generated in Secure Enclave.
Bind user/document keys to an attested app instance on the server.

### Android

Use platform-provided security primitives:

- Play Integrity API for app/device integrity verdicts.
- Android Keystore / StrongBox when available for non-exportable keys.
- Android Key Attestation where available to prove key origin and restrictions.
- BiometricPrompt / device credential for user-gated key use.
- Jetpack Security or Google Tink for standard crypto where appropriate.

Important platform constraint:

StrongBox is not present on all Android devices. The API must report the actual
security level and the backend must decide whether to accept, degrade, or block
the device.

## Security Grades

Every secure response that describes a device key or capability must report a
`securityGrade`. The backend should store this and apply policy per tenant.

Recommended values:

```text
hardware_strong
  iOS Secure Enclave or Android StrongBox/TEE with attestation/integrity
  accepted by the backend.

hardware_unattested
  Hardware-backed or OS-protected key is likely present, but the server cannot
  fully verify it.

software_protected
  Key is non-exportable through platform API but not backed by hardware, or the
  platform cannot prove hardware protection.

unsupported
  Required primitives are unavailable.
```

For passport/visa data, production policy should prefer `hardware_strong` for
employees and allow carefully reviewed fallback policy for customers only when
business requirements demand it.

## Common Bridge Response Shape

All secure actions must use this envelope:

```json
{
  "platform": "ios",
  "action": "secureCapabilitiesGet",
  "requestId": "2bcd73d4-1a64-4b63-a7fb-1555baea9d1e",
  "success": true
}
```

On error:

```json
{
  "platform": "android",
  "action": "secureKeyCreate",
  "requestId": "2bcd73d4-1a64-4b63-a7fb-1555baea9d1e",
  "success": false,
  "errorCode": "biometric_not_enrolled",
  "error": "No biometric or device credential is enrolled.",
  "retryable": false
}
```

Required common fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `platform` | string | `ios` or `android`. |
| `action` | string | Echo of the handled action. |
| `requestId` | string | Echo of request ID if provided. |
| `success` | boolean | True only when the requested operation completed. |
| `errorCode` | string | Stable machine-readable error code on failure. |
| `error` | string | Human-readable error text on failure. |
| `retryable` | boolean | Whether retrying without user/system change can work. |

Recommended error codes:

```text
unsupported
not_enrolled
already_enrolled
invalid_request
invalid_challenge
origin_not_allowed
network_not_allowed
biometric_not_available
biometric_not_enrolled
biometric_failed
user_cancelled
key_not_found
key_invalidated
key_generation_failed
attestation_failed
integrity_failed
crypto_failed
scan_cancelled
scan_quality_failed
upload_failed
server_rejected
viewer_expired
revoked
internal_error
```

## Common Request Fields

All secure requests should support:

```json
{
  "action": "secureChallengeSign",
  "requestId": "2bcd73d4-1a64-4b63-a7fb-1555baea9d1e",
  "tenantId": "tenant_hb",
  "userId": "usr_123",
  "sessionId": "sess_abc"
}
```

Required validation:

- `action` is mandatory.
- `requestId` is strongly recommended.
- `tenantId` and `userId` are mandatory for user-bound secure actions.
- Native code must not trust `tenantId`, `userId`, `caseId`, `documentId`, or
  role values by itself. The backend must verify signatures and policy.

## Data Encoding Rules

- Binary fields in bridge responses use base64url without padding unless noted.
- Large document bytes must not cross the JavaScript bridge.
- Cleartext scan bytes must never be returned to JavaScript in secure flows.
- Encrypted blobs may be uploaded directly by native code or referenced by a
  `nativeBlobRef` for a later `secureBlobUpload`.
- Hashes use SHA-256 unless an `algorithm` field says otherwise.
- Timestamps use ISO 8601 UTC, e.g. `2026-06-06T12:34:56Z`.

## Algorithm Suite

Version 1 should support this baseline suite:

```json
{
  "algorithmSuite": "v1.p256.hkdf-sha256.aes-256-gcm.ecdsa-p256-sha256",
  "documentCipher": "AES-256-GCM",
  "documentKeyBytes": 32,
  "hash": "SHA-256",
  "signing": "ECDSA-P256-SHA256",
  "keyAgreement": "P256-ECDH-HKDF-SHA256"
}
```

Allowed Android fallback when P-256 key agreement is not hardware-backed or not
available:

```json
{
  "algorithmSuite": "v1.rsa-oaep-sha256.aes-256-gcm.ecdsa-p256-sha256",
  "documentCipher": "AES-256-GCM",
  "documentKeyBytes": 32,
  "hash": "SHA-256",
  "signing": "ECDSA-P256-SHA256",
  "keyWrapping": "RSA-OAEP-SHA256"
}
```

Do not invent algorithms. Use OS crypto APIs or a reviewed standard library
such as Google Tink where OS API coverage is incomplete.

## Required Native Actions

Minimum viable secure module:

```text
secureCapabilitiesGet
secureAppEnroll
secureChallengeSign
secureKeyList
secureKeyDelete
secureDocumentScan
secureBlobUpload
secureGrantCreate
secureGrantRevoke
secureDocumentOpen
secureSessionEnd
```

Recommended later additions:

```text
secureRecoveryStart
secureRecoveryComplete
secureEnvelopeRewrap
secureAuditExport
```

## Action: secureCapabilitiesGet

Purpose:

Report native security capabilities before the web app decides which flow to
offer. This must not trigger biometric UI.

Request:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureCapabilitiesGet',
  requestId: crypto.randomUUID()
});
```

Expected iOS response:

```json
{
  "platform": "ios",
  "action": "secureCapabilitiesGet",
  "requestId": "req_001",
  "success": true,
  "moduleVersion": "1.0.0",
  "secureModuleAvailable": true,
  "appAttestation": {
    "provider": "apple_app_attest",
    "available": true
  },
  "deviceIntegrity": {
    "provider": "apple_app_attest",
    "available": true
  },
  "keyProtection": {
    "secureEnclaveAvailable": true,
    "biometricAvailable": true,
    "biometricEnrolled": true,
    "deviceCredentialAvailable": true,
    "supportedKeyPurposes": ["sign", "keyAgreement"],
    "securityGrade": "hardware_strong"
  },
  "documentCrypto": {
    "supported": true,
    "algorithmSuites": [
      "v1.p256.hkdf-sha256.aes-256-gcm.ecdsa-p256-sha256"
    ],
    "nativeBlobUpload": true,
    "nativeSecureViewer": true
  },
  "scan": {
    "documentScannerAvailable": true,
    "pdfOutput": true,
    "jpegOutput": true,
    "ocrAvailable": true,
    "qualityChecks": ["blur", "pageBounds", "minResolution", "hash"]
  }
}
```

Expected Android response:

```json
{
  "platform": "android",
  "action": "secureCapabilitiesGet",
  "requestId": "req_001",
  "success": true,
  "moduleVersion": "1.0.0",
  "secureModuleAvailable": true,
  "appAttestation": {
    "provider": "play_integrity",
    "available": true
  },
  "deviceIntegrity": {
    "provider": "play_integrity",
    "available": true
  },
  "keyProtection": {
    "strongBoxAvailable": true,
    "hardwareBackedKeystoreAvailable": true,
    "keyAttestationAvailable": true,
    "biometricAvailable": true,
    "biometricEnrolled": true,
    "deviceCredentialAvailable": true,
    "supportedKeyPurposes": ["sign", "keyAgreement", "unwrap"],
    "securityGrade": "hardware_strong"
  },
  "documentCrypto": {
    "supported": true,
    "algorithmSuites": [
      "v1.p256.hkdf-sha256.aes-256-gcm.ecdsa-p256-sha256",
      "v1.rsa-oaep-sha256.aes-256-gcm.ecdsa-p256-sha256"
    ],
    "nativeBlobUpload": true,
    "nativeSecureViewer": true
  },
  "scan": {
    "documentScannerAvailable": true,
    "pdfOutput": true,
    "jpegOutput": true,
    "ocrAvailable": false,
    "qualityChecks": ["blur", "pageBounds", "minResolution", "hash"]
  }
}
```

Native requirements:

- Must detect platform capabilities at runtime.
- Must distinguish hardware-backed, software-protected, and unsupported.
- Must not overclaim Secure Enclave/StrongBox availability.
- Must not create keys or mutate state.

## Action: secureAppEnroll

Purpose:

Create or bind the native app instance and user/device keys to a server-issued
challenge. This is the root registration flow for customer and employee apps.

The web app must first ask the backend for an enrollment challenge:

```http
POST /api/mobile/enrollment/challenge
Content-Type: application/json

{
  "tenantId": "tenant_hb",
  "userId": "usr_customer_123",
  "role": "customer",
  "platform": "ios"
}
```

Example backend response:

```json
{
  "enrollmentId": "enr_01HX",
  "challenge": "C7EKgF12e1WSfOZwsQZiO7wqXguE8m-SjFv3mXawV44",
  "expiresAt": "2026-06-06T12:34:56Z",
  "tenantId": "tenant_hb",
  "userId": "usr_customer_123",
  "requiredPolicy": {
    "requireBiometricOrDeviceCredential": true,
    "preferHardwareBacked": true,
    "allowSoftwareFallback": true
  }
}
```

Bridge request:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureAppEnroll',
  requestId: crypto.randomUUID(),
  enrollmentId: 'enr_01HX',
  tenantId: 'tenant_hb',
  userId: 'usr_customer_123',
  role: 'customer',
  challenge: 'C7EKgF12e1WSfOZwsQZiO7wqXguE8m-SjFv3mXawV44',
  expiresAt: '2026-06-06T12:34:56Z',
  displayName: 'Max Mustermann',
  keyPolicy: {
    requireBiometricOrDeviceCredential: true,
    invalidateOnBiometricChange: false,
    preferHardwareBacked: true,
    allowSoftwareFallback: true
  }
});
```

Expected iOS response:

```json
{
  "platform": "ios",
  "action": "secureAppEnroll",
  "requestId": "req_002",
  "success": true,
  "enrollmentId": "enr_01HX",
  "nativeInstanceId": "ni_ios_8c5d0d4f",
  "securityGrade": "hardware_strong",
  "appAttestation": {
    "provider": "apple_app_attest",
    "keyId": "FhZf...appAttestKeyId",
    "challenge": "C7EKgF12e1WSfOZwsQZiO7wqXguE8m-SjFv3mXawV44",
    "attestationObject": "o2NmbXRoZmlkby11MmZnYXR0U3RtdKJj...",
    "clientHashAlgorithm": "SHA-256"
  },
  "keys": [
    {
      "keyId": "key_usr_sign_v1",
      "purpose": "sign",
      "algorithm": "ECDSA-P256-SHA256",
      "publicKeySpki": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...",
      "requiresUserPresence": true,
      "biometricPolicy": "biometry_or_device_credential",
      "hardwareBacked": true,
      "attestation": {
        "provider": "bound_to_app_attest",
        "appAttestKeyId": "FhZf...appAttestKeyId"
      }
    },
    {
      "keyId": "key_usr_agree_v1",
      "purpose": "keyAgreement",
      "algorithm": "P256-ECDH-HKDF-SHA256",
      "publicKeySpki": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...",
      "requiresUserPresence": true,
      "biometricPolicy": "biometry_or_device_credential",
      "hardwareBacked": true,
      "attestation": {
        "provider": "bound_to_app_attest",
        "appAttestKeyId": "FhZf...appAttestKeyId"
      }
    }
  ]
}
```

Expected Android response:

```json
{
  "platform": "android",
  "action": "secureAppEnroll",
  "requestId": "req_002",
  "success": true,
  "enrollmentId": "enr_01HX",
  "nativeInstanceId": "ni_android_a96a0d41",
  "securityGrade": "hardware_strong",
  "appAttestation": {
    "provider": "play_integrity",
    "challenge": "C7EKgF12e1WSfOZwsQZiO7wqXguE8m-SjFv3mXawV44",
    "integrityToken": "eyJhbGciOiJSUzI1NiIs..."
  },
  "keys": [
    {
      "keyId": "key_usr_sign_v1",
      "purpose": "sign",
      "algorithm": "ECDSA-P256-SHA256",
      "publicKeySpki": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...",
      "requiresUserPresence": true,
      "biometricPolicy": "biometric_or_device_credential",
      "hardwareBacked": true,
      "strongBoxBacked": true,
      "attestation": {
        "provider": "android_key_attestation",
        "challenge": "C7EKgF12e1WSfOZwsQZiO7wqXguE8m-SjFv3mXawV44",
        "certificateChainPem": [
          "-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----"
        ]
      }
    }
  ]
}
```

Backend completion call:

```http
POST /api/mobile/enrollment/complete
Content-Type: application/json

{
  "enrollmentId": "enr_01HX",
  "nativeResponse": {
    "...": "full secureAppEnroll response"
  }
}
```

Backend must verify:

- Challenge is fresh, unexpired, and belongs to the user/session.
- iOS App Attest attestation object is valid for the app ID/team ID.
- Android Play Integrity token is valid and meets tenant policy.
- Android Key Attestation chain is valid when provided.
- Public keys are unique and not already bound to another active user unless
  explicit device-sharing policy allows it.
- Key policy matches tenant requirements.

Native requirements:

- Create non-exportable keys.
- Store private keys only in Keychain/Secure Enclave or Android Keystore.
- Never return private key material.
- User-facing biometric prompt is allowed during enrollment.
- If enrollment already exists, either return `already_enrolled` with key
  details or support `forceRotate: true`.
- Store only local key aliases, server enrollment ID, native instance ID, and
  non-sensitive metadata.

## Action: secureChallengeSign

Purpose:

Sign backend-issued challenges for login, session binding, grant approval,
document viewing, and revocation. This is the standard proof-of-possession
operation after enrollment.

Backend challenge example:

```json
{
  "challengeId": "chl_01HY",
  "challenge": "uK1N7qTCjUQu8NSsNO3C8DG1Oh0kQrSa-hcxxDgURHQ",
  "purpose": "login",
  "expiresAt": "2026-06-06T12:45:00Z",
  "displayText": "Login bei Blue Card Portal bestaetigen"
}
```

Bridge request:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureChallengeSign',
  requestId: crypto.randomUUID(),
  tenantId: 'tenant_hb',
  userId: 'usr_customer_123',
  challengeId: 'chl_01HY',
  challenge: 'uK1N7qTCjUQu8NSsNO3C8DG1Oh0kQrSa-hcxxDgURHQ',
  purpose: 'login',
  displayText: 'Login bei Blue Card Portal bestaetigen',
  requireUserPresence: true
});
```

Expected response:

```json
{
  "platform": "ios",
  "action": "secureChallengeSign",
  "requestId": "req_003",
  "success": true,
  "challengeId": "chl_01HY",
  "keyId": "key_usr_sign_v1",
  "algorithm": "ECDSA-P256-SHA256",
  "signature": "MEUCIQDYaV46m86gV0Gqf_aT...",
  "signedPayload": {
    "version": 1,
    "tenantId": "tenant_hb",
    "userId": "usr_customer_123",
    "nativeInstanceId": "ni_ios_8c5d0d4f",
    "challengeId": "chl_01HY",
    "challengeHash": "kM-3k5O9-oGv9d3gO_yC_PfEQ5Fq5sCYWnO6c3fOJvM",
    "purpose": "login",
    "createdAt": "2026-06-06T12:40:12Z"
  },
  "userPresence": {
    "required": true,
    "satisfied": true,
    "method": "biometric_or_device_credential"
  }
}
```

Native requirements:

- Canonicalize the `signedPayload` before signing.
- Include only hashes of large payloads, not raw document bytes.
- Use biometric/device credential when `requireUserPresence` is true.
- Reject stale or malformed requests.
- Redact challenge values from logs.

Backend must verify:

- Signature with the stored public key.
- Challenge freshness and purpose.
- User and tenant binding.
- Enrollment status and revocation status.
- Device/app integrity policy.

## Action: secureKeyList

Purpose:

Return local secure key metadata for diagnostics, account settings, and backend
reconciliation. This does not expose private keys and must not trigger biometric
UI.

Request:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureKeyList',
  requestId: crypto.randomUUID()
});
```

Expected response:

```json
{
  "platform": "android",
  "action": "secureKeyList",
  "requestId": "req_004",
  "success": true,
  "nativeInstanceId": "ni_android_a96a0d41",
  "keys": [
    {
      "keyId": "key_usr_sign_v1",
      "purpose": "sign",
      "algorithm": "ECDSA-P256-SHA256",
      "createdAt": "2026-06-06T12:30:00Z",
      "requiresUserPresence": true,
      "hardwareBacked": true,
      "strongBoxBacked": true,
      "invalidated": false
    }
  ]
}
```

Native requirements:

- Return metadata only.
- If a key alias exists but is invalidated, report `invalidated: true`.
- Do not silently recreate keys from this action.

## Action: secureKeyDelete

Purpose:

Delete local keys during logout, account removal, device de-registration, or
admin support flows. Backend must be informed separately, because local deletion
alone does not revoke server-side enrollment.

Request:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureKeyDelete',
  requestId: crypto.randomUUID(),
  tenantId: 'tenant_hb',
  userId: 'usr_customer_123',
  keyIds: ['key_usr_sign_v1', 'key_usr_agree_v1'],
  reason: 'user_logout_remove_device',
  requireUserPresence: true
});
```

Expected response:

```json
{
  "platform": "ios",
  "action": "secureKeyDelete",
  "requestId": "req_005",
  "success": true,
  "deletedKeyIds": ["key_usr_sign_v1", "key_usr_agree_v1"],
  "notFoundKeyIds": [],
  "requiresBackendRevocation": true
}
```

Native requirements:

- Use user presence for destructive key removal when requested.
- Delete only keys owned by the secure module.
- Return missing keys explicitly.
- Do not delete unrelated wrapper settings.

## Action: secureDocumentScan

Purpose:

Scan a passport/visa document, run optional quality/OCR checks, encrypt it
natively, create key envelopes, and return only encrypted metadata or a native
blob reference. This is the main replacement for `scanDocument` in secure apps.

Request for encrypted local blob:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureDocumentScan',
  requestId: crypto.randomUUID(),
  tenantId: 'tenant_hb',
  userId: 'usr_customer_123',
  caseId: 'case_bluecard_456',
  documentType: 'passport',
  outputFormat: 'pdf',
  mode: 'encryptOnly',
  algorithmSuite: 'v1.p256.hkdf-sha256.aes-256-gcm.ecdsa-p256-sha256',
  qualityPolicy: {
    minWidth: 1200,
    minHeight: 1600,
    rejectBlur: true,
    requirePageBounds: true,
    maxPages: 4
  },
  ocr: {
    enabled: true,
    returnTextToWeb: false,
    includeTextHashInMetadata: true
  },
  recipients: [
    {
      "recipientId": "customer:self",
      "type": "customer_device_key",
      "publicKeySpki": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE..."
    },
    {
      "recipientId": "kms:tenant_hb",
      "type": "kms_public_key",
      "kid": "kms_tenant_hb_v3",
      "publicKeySpki": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A..."
    }
  ],
  signResult: true
});
```

Request for direct native upload:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureDocumentScan',
  requestId: crypto.randomUUID(),
  tenantId: 'tenant_hb',
  userId: 'usr_customer_123',
  caseId: 'case_bluecard_456',
  documentType: 'visa',
  outputFormat: 'pdf',
  mode: 'encryptAndUpload',
  upload: {
    "url": "https://api.example.com/api/documents/blob-upload",
    "method": "PUT",
    "headers": {
      "Authorization": "Bearer upload_token_short_lived",
      "X-Upload-Id": "upl_01HZ"
    },
    "expiresAt": "2026-06-06T12:55:00Z"
  },
  recipients: [
    {
      "recipientId": "customer:self",
      "type": "customer_device_key",
      "publicKeySpki": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE..."
    },
    {
      "recipientId": "kms:tenant_hb",
      "type": "kms_public_key",
      "kid": "kms_tenant_hb_v3",
      "publicKeySpki": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A..."
    }
  ],
  signResult: true
});
```

Expected response for `encryptOnly`:

```json
{
  "platform": "ios",
  "action": "secureDocumentScan",
  "requestId": "req_006",
  "success": true,
  "documentId": "doc_local_01J0",
  "nativeBlobRef": "blobref_ios_5b16e45a",
  "mode": "encryptOnly",
  "documentType": "passport",
  "caseId": "case_bluecard_456",
  "format": "pdf",
  "cipher": {
    "algorithmSuite": "v1.p256.hkdf-sha256.aes-256-gcm.ecdsa-p256-sha256",
    "documentCipher": "AES-256-GCM",
    "iv": "xQ7XSq6WwbI9S9w6",
    "tagBytes": 16,
    "ciphertextSha256": "ZqTgB0dbw4cVh2IpzVnWKg7aGwl1k8sk8px9xG88JHg",
    "cleartextSha256": "k56QHR9X4UT1T23W1TPsOApn9KrVQVyY4n7OKM6s61g",
    "cleartextSizeBytes": 482112,
    "ciphertextSizeBytes": 482128
  },
  "envelopes": [
    {
      "envelopeId": "env_customer_self_v1",
      "recipientId": "customer:self",
      "recipientType": "customer_device_key",
      "keyWrapAlgorithm": "P256-ECDH-HKDF-SHA256-AESKW",
      "wrappedKey": "J9-Y9a34hQRmQWVH9RXaGpVQALfhbU3AXa7kF...",
      "ephemeralPublicKeySpki": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE..."
    },
    {
      "envelopeId": "env_kms_tenant_hb_v3",
      "recipientId": "kms:tenant_hb",
      "recipientType": "kms_public_key",
      "kid": "kms_tenant_hb_v3",
      "keyWrapAlgorithm": "RSA-OAEP-SHA256",
      "wrappedKey": "Vt0KZ2hW5HFd3Kc9h3Z2..."
    }
  ],
  "scan": {
    "pages": 2,
    "qualityPassed": true,
    "quality": [
      {
        "page": 1,
        "width": 2480,
        "height": 3508,
        "blurScore": 0.04,
        "pageBoundsDetected": true
      }
    ],
    "ocr": {
      "performed": true,
      "textReturned": false,
      "textSha256": "hj_JzgD4H9stcGXxU4V8sDK8HaZ6gQeM6pf88ki7h7Q"
    }
  },
  "signature": {
    "keyId": "key_usr_sign_v1",
    "algorithm": "ECDSA-P256-SHA256",
    "signedMetadataHash": "3cvtyS6ic6iJwH7e1fvC3uSGrvxVxt3yR4hHTIjcvEU",
    "signature": "MEQCIG0x6nPn..."
  }
}
```

Expected response for `encryptAndUpload`:

```json
{
  "platform": "android",
  "action": "secureDocumentScan",
  "requestId": "req_006",
  "success": true,
  "documentId": "doc_local_01J0",
  "mode": "encryptAndUpload",
  "uploaded": true,
  "upload": {
    "url": "https://api.example.com/api/documents/blob-upload",
    "uploadId": "upl_01HZ",
    "statusCode": 200,
    "bytesUploaded": 482128,
    "serverETag": "\"f1a02bd\""
  },
  "cipher": {
    "algorithmSuite": "v1.p256.hkdf-sha256.aes-256-gcm.ecdsa-p256-sha256",
    "documentCipher": "AES-256-GCM",
    "iv": "xQ7XSq6WwbI9S9w6",
    "tagBytes": 16,
    "ciphertextSha256": "ZqTgB0dbw4cVh2IpzVnWKg7aGwl1k8sk8px9xG88JHg",
    "cleartextSha256": "k56QHR9X4UT1T23W1TPsOApn9KrVQVyY4n7OKM6s61g",
    "cleartextSizeBytes": 482112,
    "ciphertextSizeBytes": 482128
  },
  "envelopes": [
    {
      "envelopeId": "env_customer_self_v1",
      "recipientId": "customer:self",
      "recipientType": "customer_device_key",
      "keyWrapAlgorithm": "P256-ECDH-HKDF-SHA256-AESKW",
      "wrappedKey": "J9-Y9a34hQRmQWVH9RXaGpVQALfhbU3AXa7kF..."
    }
  ],
  "signature": {
    "keyId": "key_usr_sign_v1",
    "algorithm": "ECDSA-P256-SHA256",
    "signedMetadataHash": "3cvtyS6ic6iJwH7e1fvC3uSGrvxVxt3yR4hHTIjcvEU",
    "signature": "MEQCIG0x6nPn..."
  }
}
```

Native requirements:

- Use native document scanner UI.
- Convert scan into requested normalized format before encryption.
- Remove EXIF/GPS/device metadata from document output.
- Generate a fresh random 256-bit DEK per document.
- Generate a fresh random IV/nonce per encryption.
- Use AES-256-GCM or a reviewed AEAD implementation.
- Include associated authenticated data (AAD):

```json
{
  "version": 1,
  "tenantId": "tenant_hb",
  "userId": "usr_customer_123",
  "caseId": "case_bluecard_456",
  "documentType": "passport",
  "createdAt": "2026-06-06T12:45:00Z",
  "algorithmSuite": "v1.p256.hkdf-sha256.aes-256-gcm.ecdsa-p256-sha256"
}
```

- Do not return cleartext document bytes.
- Clear temporary cleartext files immediately after encryption.
- Store only encrypted temporary blobs if `encryptOnly` is used.
- If upload is requested, stream encrypted bytes from native code.
- If quality policy fails, do not upload by default; return
  `scan_quality_failed`.
- Sign the final metadata when `signResult` is true.

Backend must store:

- Ciphertext blob.
- Cipher metadata and hashes.
- Envelopes.
- Signed metadata and signature.
- Scan quality metadata.
- Audit event for upload.

Backend must not need cleartext document bytes to store the upload.

## Action: secureBlobUpload

Purpose:

Upload an encrypted blob created by `secureDocumentScan` in `encryptOnly` mode.
This avoids transporting large encrypted blobs through JavaScript.

Request:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureBlobUpload',
  requestId: crypto.randomUUID(),
  nativeBlobRef: 'blobref_ios_5b16e45a',
  upload: {
    url: 'https://api.example.com/api/documents/blob-upload',
    method: 'PUT',
    headers: {
      Authorization: 'Bearer upload_token_short_lived',
      'X-Upload-Id': 'upl_01HZ'
    },
    expiresAt: '2026-06-06T12:55:00Z'
  },
  expectedCiphertextSha256: 'ZqTgB0dbw4cVh2IpzVnWKg7aGwl1k8sk8px9xG88JHg'
});
```

Expected response:

```json
{
  "platform": "ios",
  "action": "secureBlobUpload",
  "requestId": "req_007",
  "success": true,
  "nativeBlobRef": "blobref_ios_5b16e45a",
  "upload": {
    "statusCode": 200,
    "bytesUploaded": 482128,
    "ciphertextSha256": "ZqTgB0dbw4cVh2IpzVnWKg7aGwl1k8sk8px9xG88JHg",
    "serverETag": "\"f1a02bd\""
  },
  "deletedLocalBlob": true
}
```

Native requirements:

- Upload only encrypted blobs created by the secure module.
- Validate local blob hash before upload when expected hash is provided.
- Use HTTPS only.
- Support tenant-configured certificate pinning in secure builds.
- Delete local encrypted blob after successful upload unless
  `retainLocalEncryptedBlob: true` is explicitly set.
- Never upload cleartext scan bytes.

## Action: secureGrantCreate

Purpose:

Let a customer grant future document access to an Auftraggeber, employee,
role, or KMS policy without exposing the DEK to JavaScript.

The usual backend flow:

1. Backend sends the app the encrypted customer DEK envelope for a document.
2. Native app unwraps the DEK internally using the customer's local key.
3. Native app creates new policy/recipient envelope or signs a grant for HSM.
4. Web app sends signed grant package to backend.
5. Backend verifies signature and activates policy.

Request:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureGrantCreate',
  requestId: crypto.randomUUID(),
  tenantId: 'tenant_hb',
  userId: 'usr_customer_123',
  documentId: 'doc_789',
  caseId: 'case_bluecard_456',
  grantId: 'grant_01K0',
  purpose: 'blue_card_application_processing',
  validFrom: '2026-06-06T13:00:00Z',
  expiresAt: '2026-07-06T13:00:00Z',
  allowView: true,
  allowEditMetadata: true,
  allowDownload: false,
  allowPrint: false,
  customerEnvelope: {
    "envelopeId": "env_customer_self_v1",
    "recipientId": "customer:self",
    "keyWrapAlgorithm": "P256-ECDH-HKDF-SHA256-AESKW",
    "wrappedKey": "J9-Y9a34hQRmQWVH9RXaGpVQALfhbU3AXa7kF...",
    "ephemeralPublicKeySpki": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE..."
  },
  grantRecipients: [
    {
      "recipientId": "kms:tenant_hb:policy",
      "recipientType": "kms_policy",
      "kid": "kms_tenant_hb_v3",
      "publicKeySpki": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A..."
    }
  ],
  requireUserPresence: true
});
```

Expected response:

```json
{
  "platform": "ios",
  "action": "secureGrantCreate",
  "requestId": "req_008",
  "success": true,
  "grantId": "grant_01K0",
  "documentId": "doc_789",
  "grant": {
    "version": 1,
    "tenantId": "tenant_hb",
    "userId": "usr_customer_123",
    "documentId": "doc_789",
    "caseId": "case_bluecard_456",
    "purpose": "blue_card_application_processing",
    "validFrom": "2026-06-06T13:00:00Z",
    "expiresAt": "2026-07-06T13:00:00Z",
    "permissions": {
      "view": true,
      "editMetadata": true,
      "download": false,
      "print": false
    },
    "createdAt": "2026-06-06T12:59:10Z"
  },
  "newEnvelopes": [
    {
      "envelopeId": "env_grant_01K0_kms_policy",
      "recipientId": "kms:tenant_hb:policy",
      "recipientType": "kms_policy",
      "kid": "kms_tenant_hb_v3",
      "keyWrapAlgorithm": "RSA-OAEP-SHA256",
      "wrappedKey": "d4tlgCpJX80Zgs4F8uT..."
    }
  ],
  "signature": {
    "keyId": "key_usr_sign_v1",
    "algorithm": "ECDSA-P256-SHA256",
    "signedGrantHash": "9TnpvWoyN_sOqCX6H05SlIBLO6-XgG2OpmxgRsUYRek",
    "signature": "MEQCIBwpuj..."
  },
  "userPresence": {
    "required": true,
    "satisfied": true,
    "method": "biometric_or_device_credential"
  }
}
```

Native requirements:

- Never return raw DEK.
- User presence is required by default.
- Grant payload must be canonicalized before signing.
- Grant must include explicit purpose and expiry.
- Native code must reject grants with missing document ID, missing purpose, or
  expiry beyond tenant maximum if the max is supplied in request policy.

Backend must verify:

- Customer signature.
- Customer owns or controls the document.
- Customer envelope can be used only by the customer key.
- New envelopes match accepted grant policy.
- Grant is not superseded by a later revoke.

## Action: secureGrantRevoke

Purpose:

Let a customer revoke all future access for a document, case, Auftraggeber,
employee, or role. This is the key product promise.

Request:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureGrantRevoke',
  requestId: crypto.randomUUID(),
  tenantId: 'tenant_hb',
  userId: 'usr_customer_123',
  revokeId: 'rev_01K1',
  scope: {
    type: 'document',
    documentId: 'doc_789'
  },
  reason: 'customer_withdrawn_consent',
  effectiveAt: '2026-06-06T14:00:00Z',
  requireUserPresence: true
});
```

Expected response:

```json
{
  "platform": "android",
  "action": "secureGrantRevoke",
  "requestId": "req_009",
  "success": true,
  "revokeId": "rev_01K1",
  "revocation": {
    "version": 1,
    "tenantId": "tenant_hb",
    "userId": "usr_customer_123",
    "scope": {
      "type": "document",
      "documentId": "doc_789"
    },
    "reason": "customer_withdrawn_consent",
    "effectiveAt": "2026-06-06T14:00:00Z",
    "createdAt": "2026-06-06T13:58:30Z"
  },
  "signature": {
    "keyId": "key_usr_sign_v1",
    "algorithm": "ECDSA-P256-SHA256",
    "signedRevocationHash": "TO39V4Zp5UP4AzDxYu3NdAcExxWsT7nAh2hEiCP3BmI",
    "signature": "MEYCIQDORa..."
  },
  "userPresence": {
    "required": true,
    "satisfied": true,
    "method": "biometric_or_device_credential"
  }
}
```

Backend behavior after verified revocation:

- Mark all matching grants as revoked.
- Stop issuing future viewer tokens / KMS decrypt approvals.
- Reject active sessions at next policy check.
- Optionally push a session termination event to active employee apps.
- Preserve audit history.
- Do not delete legally required records unless separate erasure policy allows
  deletion.

Native requirements:

- Require user presence by default.
- Sign a precise revocation object.
- Do not rely on client clock for final policy; backend decides effective time.

## Action: secureDocumentOpen

Purpose:

Open an encrypted document in a native secure viewer without returning cleartext
bytes to JavaScript. This action is primarily for employee apps, but can also be
used by customer apps for self-view.

Backend flow before opening:

1. Employee requests document view in web app.
2. Backend verifies role, grant, revocation state, purpose, and case assignment.
3. Backend creates a short-lived view session and returns encrypted blob URL,
   document metadata, and a KMS/viewer envelope.
4. Native app opens secure viewer and performs decrypt/view internally.

Bridge request:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureDocumentOpen',
  requestId: crypto.randomUUID(),
  tenantId: 'tenant_hb',
  userId: 'usr_employee_777',
  viewSessionId: 'view_01K2',
  documentId: 'doc_789',
  purpose: 'blue_card_application_processing',
  requireUserPresence: true,
  encryptedBlob: {
    "url": "https://api.example.com/api/documents/doc_789/blob",
    "headers": {
      "Authorization": "Bearer view_token_short_lived"
    },
    "ciphertextSha256": "ZqTgB0dbw4cVh2IpzVnWKg7aGwl1k8sk8px9xG88JHg",
    "expiresAt": "2026-06-06T14:10:00Z"
  },
  viewerEnvelope: {
    "envelopeId": "env_view_01K2",
    "recipientId": "employee:usr_employee_777",
    "keyWrapAlgorithm": "kms_session_unwrap",
    "wrappedKey": "server_policy_token_or_wrapped_dek"
  },
  viewerPolicy: {
    "allowDownload": false,
    "allowPrint": false,
    "watermark": "usr_employee_777 - 2026-06-06T14:05Z",
    "expiresAt": "2026-06-06T14:15:00Z"
  }
});
```

Expected response when viewer opens:

```json
{
  "platform": "ios",
  "action": "secureDocumentOpen",
  "requestId": "req_010",
  "success": true,
  "viewSessionId": "view_01K2",
  "documentId": "doc_789",
  "viewer": {
    "opened": true,
    "secureMode": true,
    "downloadAllowed": false,
    "printAllowed": false,
    "watermarkApplied": true,
    "expiresAt": "2026-06-06T14:15:00Z"
  }
}
```

Expected follow-up event when closed:

```json
{
  "platform": "ios",
  "action": "secureDocumentClosed",
  "success": true,
  "viewSessionId": "view_01K2",
  "documentId": "doc_789",
  "closedAt": "2026-06-06T14:08:20Z",
  "durationSeconds": 190
}
```

Native requirements:

- Fetch encrypted blob natively over HTTPS.
- Verify ciphertext hash.
- Unwrap/decrypt internally.
- Render in a native viewer or isolated secure WebView that is not the normal
  app WebView.
- Do not expose cleartext to JavaScript callbacks.
- Android must set `FLAG_SECURE` while secure viewer is visible.
- iOS must detect screen capture/recording where possible and obscure content
  or emit a security event. iOS cannot fully prevent all external capture.
- Apply visible watermark when provided.
- Clear decrypted memory/temp files on close.
- Emit close/audit events.

Backend must:

- Issue short-lived view tokens only after policy check.
- Re-check revocation before KMS/session unwrap.
- Revoke active view sessions when customer revokes access.
- Store view-open and view-close audit events.

## Action: secureSessionEnd

Purpose:

End native secure sessions, clear temporary encrypted blobs, close secure viewer,
and optionally lock local keys until next user presence.

Request:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureSessionEnd',
  requestId: crypto.randomUUID(),
  reason: 'logout',
  closeViewer: true,
  deleteTemporaryBlobs: true
});
```

Expected response:

```json
{
  "platform": "android",
  "action": "secureSessionEnd",
  "requestId": "req_011",
  "success": true,
  "closedViewer": true,
  "deletedTemporaryBlobCount": 2,
  "locked": true
}
```

Native requirements:

- Close secure viewer if open.
- Delete temporary blobs created by secure scan/open flows.
- Keep long-term private keys unless key deletion was explicitly requested.
- Clear in-memory session state.

## Recommended Later Action: secureRecoveryStart

Purpose:

Start account/device recovery when a customer loses a device. Recovery must be
mostly backend/product policy, but native should support proof-of-possession
for a newly enrolled device.

Request:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureRecoveryStart',
  requestId: crypto.randomUUID(),
  tenantId: 'tenant_hb',
  userId: 'usr_customer_123',
  recoveryChallenge: 'wK1usFF...',
  recoveryMethod: 'support_verified'
});
```

Expected response:

```json
{
  "platform": "ios",
  "action": "secureRecoveryStart",
  "requestId": "req_012",
  "success": true,
  "recoveryAttemptId": "rec_01K3",
  "requiresBackendApproval": true
}
```

Do not implement automatic recovery that silently restores customer document
keys without strong backend approval.

## Recommended Later Action: secureEnvelopeRewrap

Purpose:

Rewrap a DEK from one envelope to another without exposing the raw DEK to
JavaScript. This is useful for key rotation, KMS migration, or adding a new
customer device.

Request:

```js
window.webkit.messageHandlers.swiftBridge.postMessage({
  action: 'secureEnvelopeRewrap',
  requestId: crypto.randomUUID(),
  tenantId: 'tenant_hb',
  userId: 'usr_customer_123',
  documentId: 'doc_789',
  sourceEnvelope: {
    "envelopeId": "env_customer_self_v1",
    "wrappedKey": "J9-Y9a34..."
  },
  targetRecipient: {
    "recipientId": "customer:new_device",
    "type": "customer_device_key",
    "publicKeySpki": "MFkwEwYH..."
  },
  requireUserPresence: true
});
```

Expected response:

```json
{
  "platform": "android",
  "action": "secureEnvelopeRewrap",
  "requestId": "req_013",
  "success": true,
  "documentId": "doc_789",
  "newEnvelope": {
    "envelopeId": "env_customer_new_device_v1",
    "recipientId": "customer:new_device",
    "keyWrapAlgorithm": "P256-ECDH-HKDF-SHA256-AESKW",
    "wrappedKey": "Xk8Ql..."
  },
  "signature": {
    "keyId": "key_usr_sign_v1",
    "algorithm": "ECDSA-P256-SHA256",
    "signature": "MEUCIF..."
  }
}
```

## End-to-End Flow: Customer Enrollment

```mermaid
sequenceDiagram
  participant Web as Web app in wrapper
  participant Native as Native secure bridge
  participant Backend as Backend
  participant Store as Keychain/Keystore

  Web->>Backend: POST /enrollment/challenge
  Backend-->>Web: enrollmentId + challenge
  Web->>Native: secureAppEnroll(challenge, userId, tenantId)
  Native->>Store: Create app/user keys
  Native-->>Web: attestation + public keys
  Web->>Backend: POST /enrollment/complete
  Backend-->>Web: enrolled
```

## End-to-End Flow: Customer Uploads Passport

```mermaid
sequenceDiagram
  participant Web as Web app in wrapper
  participant Native as Native secure bridge
  participant Backend as Backend
  participant KMS as KMS/HSM

  Web->>Backend: POST /documents/upload-intent
  Backend->>KMS: Get tenant KMS wrapping public key
  Backend-->>Web: upload URL + recipients
  Web->>Native: secureDocumentScan(encryptAndUpload)
  Native->>Native: Scan + normalize + quality checks
  Native->>Native: Generate DEK + AES-GCM encrypt
  Native->>Native: Wrap DEK for customer and KMS
  Native->>Backend: PUT encrypted blob
  Native-->>Web: encrypted metadata + envelopes + signature
  Web->>Backend: POST /documents/complete
  Backend-->>Web: stored document ID
```

## End-to-End Flow: Customer Grants Access

```mermaid
sequenceDiagram
  participant Web as Web app in wrapper
  participant Native as Native secure bridge
  participant Backend as Backend
  participant KMS as KMS/HSM

  Web->>Backend: POST /documents/doc_789/grant-intent
  Backend-->>Web: customer envelope + KMS recipient
  Web->>Native: secureGrantCreate(...)
  Native->>Native: User presence
  Native->>Native: Unwrap customer envelope internally
  Native->>Native: Create policy envelope + sign grant
  Native-->>Web: signed grant + envelope
  Web->>Backend: POST /documents/doc_789/grants
  Backend->>KMS: Activate grant policy
  Backend-->>Web: grant active
```

## End-to-End Flow: Employee Views Document

```mermaid
sequenceDiagram
  participant Web as Employee web app in wrapper
  participant Native as Employee native secure bridge
  participant Backend as Backend
  participant KMS as KMS/HSM

  Web->>Backend: POST /documents/doc_789/view-intent
  Backend->>Backend: Check role, grant, revocation, purpose
  Backend->>KMS: Create short-lived viewer session
  Backend-->>Web: encrypted blob URL + viewer envelope
  Web->>Native: secureDocumentOpen(...)
  Native->>Backend: Fetch encrypted blob
  Native->>Native: Verify hash + decrypt internally
  Native->>Native: Show secure viewer with watermark
  Native-->>Web: viewer opened
  Native-->>Web: secureDocumentClosed event
```

## End-to-End Flow: Customer Revokes Future Access

```mermaid
sequenceDiagram
  participant Web as Customer web app in wrapper
  participant Native as Native secure bridge
  participant Backend as Backend
  participant KMS as KMS/HSM

  Web->>Backend: POST /revocation/challenge
  Backend-->>Web: revokeId + context
  Web->>Native: secureGrantRevoke(...)
  Native->>Native: User presence
  Native-->>Web: signed revocation
  Web->>Backend: POST /revocations
  Backend->>KMS: Disable future unwrap/view policy
  Backend->>Backend: Mark grants revoked
  Backend-->>Web: revoked
```

## WebView Hardening Required for Secure Builds

The secure module must not be enabled in a generic, arbitrary-URL WebView
without additional checks.

Required iOS changes:

- Validate `WKScriptMessage.frameInfo.securityOrigin` or equivalent origin
  information before accepting secure actions.
- Maintain an `allowedOrigins` list in native secure configuration.
- Reject secure actions from local demo pages unless debug mode explicitly
  allows them.
- Enforce HTTPS for remote secure web apps.
- Enable App Transport Security defaults; do not allow arbitrary insecure loads
  in production secure builds.
- Store sensitive local metadata in Keychain, not `UserDefaults`.
- Redact secure request bodies in logs.

Required Android changes:

- Set `android:usesCleartextTraffic="false"` for secure builds.
- Set `android:allowBackup="false"` for secure builds unless encrypted backup
  policy is explicitly designed.
- Restrict exported activities and deep-link start URLs.
- Reject secure actions unless current WebView URL origin is allow-listed.
- Disable mixed content in secure builds.
- Consider disabling file/content access for remote production pages.
- Use Safe Browsing where available.
- Apply `FLAG_SECURE` for secure viewer screens.
- Store sensitive local metadata in Keystore-backed storage, not plain
  SharedPreferences.
- Redact secure request bodies in logs.

Recommended shared config:

```json
{
  "secureMode": true,
  "allowedOrigins": [
    "https://bluecard.example.com",
    "https://tenant-hb.example.com"
  ],
  "allowLocalDebugOrigin": false,
  "requireHttps": true,
  "certificatePinning": {
    "enabled": true,
    "pins": [
      {
        "host": "api.example.com",
        "sha256": "base64-pin-value"
      }
    ]
  }
}
```

## Backend Contract Summary

The native wrapper is not enough by itself. The backend must provide at least:

```text
POST /api/mobile/enrollment/challenge
POST /api/mobile/enrollment/complete
POST /api/mobile/challenge
POST /api/mobile/challenge/verify

POST /api/documents/upload-intent
PUT  /api/documents/blob-upload
POST /api/documents/complete

POST /api/documents/{documentId}/grant-intent
POST /api/documents/{documentId}/grants

POST /api/revocation/challenge
POST /api/revocations

POST /api/documents/{documentId}/view-intent
GET  /api/documents/{documentId}/blob
POST /api/documents/{documentId}/audit
```

Backend persistent objects:

```text
User
Tenant
NativeAppInstance
UserDeviceKey
Document
DocumentBlob
DocumentEnvelope
Grant
Revocation
ViewSession
AuditEvent
```

Backend must never treat native client responses as policy decisions. Native
signatures prove possession and user presence. Backend decides authorization.

## Audit Requirements

Native should emit or return enough metadata for backend audit:

```json
{
  "eventType": "document.view.opened",
  "tenantId": "tenant_hb",
  "userId": "usr_employee_777",
  "documentId": "doc_789",
  "viewSessionId": "view_01K2",
  "nativeInstanceId": "ni_android_a96a0d41",
  "createdAt": "2026-06-06T14:05:01Z",
  "securityGrade": "hardware_strong"
}
```

Audit events should exist for:

- Enrollment challenge issued.
- Enrollment completed.
- Key rotated/deleted.
- Document scanned.
- Document encrypted.
- Encrypted blob uploaded.
- Grant created.
- Grant revoked.
- View session issued.
- Viewer opened.
- Viewer closed.
- Viewer denied due to revocation.
- Secure error events, excluding sensitive payloads.

## Data Privacy Rules

For passport/visa documents:

- Never log document bytes, OCR text, MRZ text, or base64 payloads.
- Never include cleartext document bytes in bridge responses.
- Avoid returning OCR text to web by default. Prefer text hashes or backend-side
  processing inside a controlled secure environment.
- Strip EXIF and camera metadata before encryption.
- Use short-lived upload/view tokens.
- Watermark employee views.
- Disable downloads/printing unless policy explicitly allows them.
- Make revocation clear to the user: it blocks future platform access, not
  copies already made outside the platform.

## Implementation Structure

Recommended iOS files:

```text
ios/swiftHTMLWebviewApp/Models/SecureBridge.swift
ios/swiftHTMLWebviewApp/Models/SecureKeyStore.swift
ios/swiftHTMLWebviewApp/Models/SecureAppAttest.swift
ios/swiftHTMLWebviewApp/Models/SecureDocumentCrypto.swift
ios/swiftHTMLWebviewApp/Models/SecureDocumentUploader.swift
ios/swiftHTMLWebviewApp/Views/SecureDocumentViewer.swift
```

Recommended Android files:

```text
android/app/src/main/java/com/ilass/swifthtmlwebviewapp/security/SecureBridge.java
android/app/src/main/java/com/ilass/swifthtmlwebviewapp/security/SecureKeyStore.java
android/app/src/main/java/com/ilass/swifthtmlwebviewapp/security/SecureIntegrity.java
android/app/src/main/java/com/ilass/swifthtmlwebviewapp/security/SecureDocumentCrypto.java
android/app/src/main/java/com/ilass/swifthtmlwebviewapp/security/SecureDocumentUploader.java
android/app/src/main/java/com/ilass/swifthtmlwebviewapp/security/SecureDocumentViewerActivity.java
```

Dispatch integration:

- Add secure action cases in `ContentView.handleScriptMessage` on iOS.
- Add secure action cases in `MainActivity.NativeBridge.postMessage` on
  Android.
- Secure actions should be delegated to a separate bridge class instead of
  expanding the main view/activity further.

## Backward Compatibility

Do not change existing action behavior:

```text
scanDocument
takePhoto
scanBarcode
settingsGet
settingsSet
```

Add secure variants:

```text
secureDocumentScan
secureDocumentOpen
secureAppEnroll
secureChallengeSign
```

Existing demo pages may expose buttons for secure actions only in debug mode.
Production products should call these actions from the hosted web app after
backend challenge negotiation.

## Store / Export Compliance Notes

The secure module uses encryption and must be declared correctly in app store
metadata.

Implementation guidance:

- Use OS-provided standard crypto where possible.
- Do not implement proprietary crypto.
- Do not include custom cryptographic algorithms.
- For iOS, document that the app uses standard Apple security APIs, Keychain,
  Secure Enclave where available, HTTPS, and AES-GCM/ECDSA/ECDH.
- For Android, document that the app uses Android Keystore/StrongBox where
  available, Play Integrity, HTTPS, and standard algorithms.
- Get legal/export review before distribution in regions with additional crypto
  filing requirements.

## Acceptance Criteria

The secure module is acceptable when all of these are true:

- `secureCapabilitiesGet` correctly reports support on simulator/emulator and
  real devices.
- Enrollment completes with server-verified App Attest on iOS.
- Enrollment completes with server-verified Play Integrity on Android.
- Android key attestation is included when available.
- Private keys are never exportable.
- Secure document scan never returns cleartext image/PDF data to JavaScript.
- Encrypted document blobs decrypt successfully in backend/native test harness.
- Grant creation signs a canonical grant and never returns raw DEK.
- Revocation signs a canonical revocation and backend denies future views.
- Secure viewer opens encrypted documents and does not expose bytes to JS.
- Android secure viewer uses `FLAG_SECURE`.
- Sensitive payloads are not printed in native logs.
- Secure actions are rejected from non-allow-listed origins.
- Existing non-secure bridge actions still work unchanged.

## Test Matrix

Minimum test devices:

```text
iPhone with Face ID and Secure Enclave
iPhone/iPad simulator, expected reduced capability
Android device with StrongBox
Android device with TEE but no StrongBox
Android emulator, expected reduced capability
Android device without biometric enrollment
Android device with biometric enrollment changed after key creation
```

Test cases:

```text
Capabilities report expected security grade.
Enrollment succeeds with valid challenge.
Enrollment fails with expired challenge.
Challenge signing requires user presence.
Signing fails cleanly when biometric is cancelled.
Key invalidation is reported after biometric set changes if policy requires it.
Secure scan rejects low-quality image when policy requires it.
Secure scan returns no cleartext bytes.
Encrypted upload hash matches backend hash.
Backend verifies signed scan metadata.
Grant create returns signed grant and new envelope.
Revocation prevents new view sessions.
Already-open viewer expires or is closed after revocation event.
Secure session end deletes temporary blobs.
Non-allowed origin cannot call secure actions.
Debug local origin can call secure actions only when explicitly enabled.
```

## References

Primary platform references to use during implementation:

- Apple App Attest / DeviceCheck: `https://developer.apple.com/documentation/DeviceCheck/establishing-your-app-s-integrity`
- Apple Secure Enclave key protection: `https://developer.apple.com/documentation/Security/protecting-keys-with-the-secure-enclave`
- Android Play Integrity verdicts: `https://developer.android.com/google/play/integrity/verdicts`
- Android Key Attestation: `https://source.android.com/security/keystore/attestation`
- Android hardware-backed key pairs: `https://developer.android.com/privacy-and-security/security-key-attestation`
