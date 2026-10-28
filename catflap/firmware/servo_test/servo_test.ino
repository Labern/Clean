// Flap Guard — step 2: find the servo's two angles.
// Type an angle (0-180) in the Serial Monitor and press Enter; the arm moves there.
// Note the angle where the clip is fully shut (LOCK) and fully open (OPEN).
// Board: ESP32-C3 SuperMini. Library: "ESP32Servo".
#include <ESP32Servo.h>

const int SERVO_PIN = 4;
Servo servo;

void setup() {
  Serial.begin(115200);
  servo.attach(SERVO_PIN, 500, 2400);  // MG90S pulse range in microseconds
  servo.write(90);
  Serial.println("type an angle 0-180");
}

void loop() {
  if (Serial.available()) {
    int a = Serial.parseInt();
    if (a >= 0 && a <= 180) { servo.write(a); Serial.printf("-> %d\n", a); }
    while (Serial.available()) Serial.read();
  }
}
