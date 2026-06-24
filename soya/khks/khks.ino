const int numBands = 16;

int bandValues[numBands];

void setup() { Serial.begin(115200); }

void loop() {

  if (Serial.available() >= numBands) {

    for (int i = 0; i < numBands; i++) {

      bandValues[i] = Serial.read();
    }

    // シリアルモニタ確認用
    for (int i = 0; i < numBands; i++) {

      Serial.print(bandValues[i]);

      Serial.print(" ");
    }

    Serial.println();
  }
}