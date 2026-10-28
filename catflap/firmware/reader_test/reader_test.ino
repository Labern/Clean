// Flap Guard — step 1: bench test the chip reader.
// Prints every chip the WL-134 sees, e.g. "CHIP 826 098100123456".
// Board: ESP32-C3 SuperMini. Library: "Rfid134 by Makuna".
#include <Rfid134.h>

const int RFID_RX = 3;   // WL-134 TX → divider → GPIO3

class RfidNotify {
public:
  static void OnError(Rfid134_Error code) { Serial.printf("read error %d\n", code); }
  static void OnPacketRead(const Rfid134Reading& r) {
    Serial.printf("CHIP %03u %06lu%06lu\n", r.country,
                  (unsigned long)(r.id / 1000000), (unsigned long)(r.id % 1000000));
  }
};

Rfid134<HardwareSerial, RfidNotify> rfid(Serial1);

void setup() {
  Serial.begin(115200);
  Serial1.begin(9600, SERIAL_8N2, RFID_RX, -1);  // receive only
  rfid.begin();
  Serial.println("ready - hold a cat near the coil");
}

void loop() { rfid.loop(); }
