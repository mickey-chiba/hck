#include <Wire.h>
#include "Adafruit_TCS34725.h"

Adafruit_TCS34725 tcs(
  TCS34725_INTEGRATIONTIME_24MS,
  TCS34725_GAIN_4X
);

void setup() {
  Serial.begin(115200);

  if (!tcs.begin()) {
    while (1); // センサ未検出停止
  }

  delay(500);
}



void loop() {
  uint16_t r, g, b, c;
  tcs.getRawData(&r, &g, &b, &c);

  if (c > 0) {

    int rr = (int)((float)r / c * 255.0);
    int gg = (int)((float)g / c * 255.0);
    int bb = (int)((float)b / c * 255.0);


    rr = constrain(rr, 0, 255);
    gg = constrain(gg, 0, 255);
    bb = constrain(bb, 0, 255);

    Serial.print(rr);
    Serial.print(",");
    Serial.print(gg);
    Serial.print(",");
    Serial.println(bb);
  }

  delay(5); 
}