# HARDWARE DEVICE BINDING & ATTESTATION
**Amrita BLE Proximity Attendance Platform**  

---

## 1. Key Generation & Storage

To prevent attendance proxying and credentials sharing:
1. Upon initial login or device setup, the mobile application invokes [`DeviceBindingService`](file:///C:/Users/PRIYANRAJ%20J/.gemini/antigravity/scratch/attendance-ble-platform/lib/ble/device_binding_service.dart).
2. On Android:
   - Key pair is generated inside the Android Keystore Provider (`KeyProperties.PURPOSE_SIGN`).
   - Private key material is marked non-exportable and protected by hardware-backed Secure OS / StrongBox where available.
   - Fallback: Secure local storage (`flutter_secure_storage`) with OS-level hardware-backed AES encryption.
3. On iOS:
   - Key pair generated inside Secure Enclave using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

---

## 2. Public Key Registration & Fingerprint

The client transmits the PEM-encoded public key to `POST /api/v1/devices/register`:
- Backend calculates SHA-256 fingerprint:
  $$\text{fingerprint} = \text{hex\_encode}(\text{SHA-256}(\text{DER}(\text{PublicKey})))$$
- Backend revokes any previously registered device keys for the student to maintain a strict 1-student-to-1-hardware mapping.
- Database records device with `attestation_status = 'key_registered'`.

---

## 3. Remote Attestation Roadmap

In enterprise production deployments requiring SafetyNet / Play Integrity / App Attest verification:
- Android: Play Integrity API token passed alongside public key; verified against Google Play backend.
- iOS: Apple App Attest service validates attestation statement and certifies public key was created inside legitimate Apple hardware.
- Upon successful certificate chain verification, backend elevates `attestation_status` to `'hardware_attested'`.
