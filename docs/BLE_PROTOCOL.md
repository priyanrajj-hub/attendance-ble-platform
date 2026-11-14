# BLUETOOTH LOW ENERGY (BLE) PROTOCOL SPECIFICATION
**Amrita BLE Proximity Attendance Platform**  

---

## 1. BLE Advertising Format

The faculty broadcasting device acts as a BLE peripheral advertising a custom manufacturer data payload.

- **Service UUID**: `00000001-a1b2-c3d4-e5f6-7a8b9c0d1e2f`
- **Manufacturer ID**: `0xFFFF` (Custom Experimental / Internal University Identifier)
- **Advertising Mode**: `AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY`
- **Tx Power Level**: `AdvertiseSettings.ADVERTISE_TX_POWER_HIGH`

### Payload Structure

| Offset (Bytes) | Length | Field Description | Example Value |
|---|---|---|---|
| `0` | 1 | Protocol Version (`0x02`) | `0x02` |
| `1` | 1 | Epoch Rotation Sub-Step | `0x00` |
| `2..17` | 16 | 128-bit Truncated HMAC-SHA256 Challenge | `4f5a8b2c1d3e9f0a5b6c7d8e9f0a1b2c` |

---

## 2. Dynamic Challenge Rotation Algorithm

1. Rotation period: $T_{\text{rot}} = 20 \text{ seconds}$.
2. Synchronized Unix Epoch Step:
   $$S = \lfloor \frac{\text{epoch\_seconds}}{20} \rfloor$$
3. Message Buffer:
   $$M = \text{session\_id} \parallel S$$
4. HMAC Computation:
   $$H = \text{HMAC-SHA256}(K = \text{session\_secret}, M)$$
5. Output Challenge:
   $$\text{Challenge} = \text{hex\_encode}(H[0..15])$$ (32 uppercase/lowercase hex characters).

---

## 3. Peripheral Filtering & Noise Rejection

The student scanner ignores irrelevant ambient BLE noise:
- Standard 16-bit and 32-bit Bluetooth SIG devices (headphones, smart TVs, Apple AirTags, wearable fitness bands) mapped to base UUID `0000xxxx-0000-1000-8000-00805f9b34fb` are strictly filtered out in [`lib/ble/ble_constants.dart`](file:///C:/Users/PRIYANRAJ%20J/.gemini/antigravity/scratch/attendance-ble-platform/lib/ble/ble_constants.dart).
- Only advertisements matching the university attendance UUID or bearing the custom manufacturer header are dispatched to the check-in controller.
