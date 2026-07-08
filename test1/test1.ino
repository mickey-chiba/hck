#include <WiFiS3.h>
#include <WiFiUdp.h>

const char ssid[] = "Buffalo-2G-1710";
const char pass[] = "g3b5ks5tuk5fm";

WiFiUDP udp;

const int port = 4286;

float currentValue = 0.0;
float receivedValue = 0.0;
float number = 1.0;
float preValue = 7000.0;
bool roundMode = false;
bool start = false;
// bool ok = false;
const int ID = 1;
//可変テンポ演奏で使う変数
float musicalTime = 0;
unsigned long lastTime = 0;
const int N = 28;
bool          noteOnSent[N]  = {false};
bool          noteOffSent[N] = {false};
bool          playing         = false;
bool processingReady = false;
unsigned long playStartms    = 0;
bool          waitingToStart = false;
float         roundDelay     = 0;
bool          bpmreceivedonce = false; // BPMが初めて届いたかのフラグ
bool first = false;
long long offsetUs = 0;





void setup() {
  Serial.begin(115200);

  Serial.println("親機接続中...");

  while (WiFi.begin(ssid, pass)!= WL_CONNECTED) {

    delay(1000);

    Serial.println("接続試行...");
  }
  delay(1000);
  // Serial.println("接続成功");

  // Serial.print("子機IP: ");
  // Serial.println(WiFi.localIP());

  udp.begin(port);

  Serial.println("UDP待機開始");
  

}
// void loop(){
//   int packetSize = udp.parsePacket();

//   if (packetSize > 0) {
//     byte buffer[8];
//     udp.read(buffer, 8);
//     int sequence;
//     float receivedValue;
//     memcpy(&sequence, buffer, 4);

//     memcpy(&receivedValue, buffer + 4, 4);
//     // Serial.print("Received BPM=");
//     // Serial.println(receivedValue);
//     byte reply[8];
//     // sequence返却
//     memcpy(reply, &sequence, 4);

//     // deviceID返却
//     memcpy(reply + 4, &ID, 4);


//     udp.beginPacket(udp.remoteIP(), port);
//     udp.write(reply, 8);
//     // Serial.print("sequence=");
//     // Serial.println(sequence);

//     // Serial.print("deviceID=");
//     // Serial.println(ID);
//     udp.endPacket();
//     unsigned long t = millis();
//     Serial.print("reply=");
//     Serial.println(t);
//   }
// }
void loop() {

  int packetSize = udp.parsePacket();

  if (packetSize > 0) {

    unsigned long rxTime = micros();

    byte buffer[16];
    udp.read(buffer, packetSize);

    int sequence;
    memcpy(&sequence, buffer, 4);
    if(sequence == -1){
      uint64_t pcTime;

      memcpy(&pcTime, buffer + 4, 8);
      uint64_t localTime = micros();

      offsetUs = (long long)pcTime - localTime;

      return;
    }    
    float receivedValue;

    memcpy(&receivedValue, buffer + 4, 4);
    uint64_t correctTime = micros() + offsetUs;

    byte reply[16];

    memcpy(reply, &sequence, 4);
    memcpy(reply + 4, &ID, 4);
    uint32_t t = (uint32_t)correctTime;
    memcpy(reply + 8, &t, 4);

    // unsigned long txTime = millis();

    // Serial.print("RX=");
    // Serial.print(rxTime);

    // Serial.print(" TX=");
    // Serial.print(txTime);

    // Serial.print(" diff=");
    // Serial.println(txTime - rxTime);

    udp.beginPacket(udp.remoteIP(), udp.remotePort());
    udp.write(reply, 12);
    udp.endPacket();
  }
}
