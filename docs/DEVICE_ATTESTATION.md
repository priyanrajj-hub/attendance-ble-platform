# HARDWARE DEVICE BINDING & REMOTE ATTESTATION ARCHITECTURE
**Amrita BLE Proximity Attendance Platform**  

---

## 1. Trust Hierarchy & Attestation Tiers

To prevent proxy attendance and emulator spoofing, the platform defines a clear two-tier attestation hierarchy:

```
[Tier 1: Key Registration ('key_registered')]
  ├── Enrolls client-generated ECDSA P-256 / RSA public key
  ├── Replaces existing device (strict 1:1 user-to-device mapping)
  └── SECURITY BOUNDARY: Authenticates device ownership; does NOT prove hardware isolation
                         without remote attestation statement.

[Tier 2: Hardware Attested ('hardware_attested')]
  ├── 1. Client requests challenge: POST /api/v1/devices/attestation-challenge
  ├── 2. Client generates key in hardware Keystore / Secure Enclave with challenge
  ├── 3. Client submits certificate chain / Play Integrity token
  ├── 4. Backend validates X.509 Key Attestation extension (1.3.6.1.4.1.11129.2.1.17)
  └── SECURITY BOUNDARY: Cryptographically verifies key generation inside TEE / StrongBox.
```

---

## 2. Remote Attestation Verification Flow

```mermaid
sequenceDiagram
    autonumber
    participant App as Mobile App
    participant API as FastAPI Backend
    participant TEE as Android Keystore / Apple Secure Enclave
    participant DB as PostgreSQL 16

    App->>API: POST /api/v1/devices/attestation-challenge
    API->>DB: INSERT device_attestation_challenges (256-bit nonce)
    API-->>App: 201 Created (challenge, expires_at)

    App->>TEE: Generate KeyPair(challenge=nonce, purpose=SIGN)
    TEE-->>App: Return (PublicKey, CertificateChain)

    App->>API: POST /api/v1/devices/register (publicKey, attestation_statement, challenge)
    API->>DB: Validate & consume challenge
    API->>API: Verify X.509 cert chain & OID 1.3.6.1.4.1.11129.2.1.17
    alt Attestation Valid
        API->>DB: INSERT Device (attestation_status='hardware_attested')
        API-->>App: 201 Created (hardware_attested)
    else Invalid Statement
        API-->>App: 400 Bad Request (Attestation rejected)
    else No Statement Provided
        API->>DB: INSERT Device (attestation_status='key_registered')
        API-->>App: 201 Created (key_registered)
    end
```

---

## 3. Explicit Security Claims & Limitations

1. **Without Hardware Attestation (`key_registered`)**:
   - The server verifies that check-ins originate from the registered public key.
   - However, a student running a modified client or software emulator could export or generate keys in software.
2. **With Hardware Attestation (`hardware_attested`)**:
   - Google hardware root certificate chain guarantees private keys never leave the hardware security module (StrongBox or ARM TrustZone).
   - Keys cannot be extracted or cloned to other devices.
