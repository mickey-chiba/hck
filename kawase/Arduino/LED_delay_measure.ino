#include <Arduino.h>
#include <WiFiS3.h>
#include <WiFiUdp.h>

const char ssid[] = "WiFi_bro_colstra"; // Wi-Fiネットワークの名称
const char pass[] = "wf215nt109rt";     // Wi-Fiのパスワード

WiFiUDP udp;
const int port    = 4286; // ポート番号
const int LED_PIN = 3;    // 計測対象のLEDピン番号

float         currentBPM  = 0.0;  // 現在のBPM
unsigned long receiveTime = 0;    // 直近のBPM受信時刻（ms）
unsigned long prevLedTime = 0;    // 前回LED切り替え時刻（ms）
unsigned long expectedTime = 0;   // 次に点灯すべき期待時刻（ms）
bool          ledOn        = false;

void setup()
{
    Serial.begin(115200);
    pinMode(LED_PIN, OUTPUT);
    pinMode(LED_BUILTIN, OUTPUT);

    // Wi-Fi接続
    while (WiFi.begin(ssid, pass) != WL_CONNECTED) {
        delay(1000);
    }
    // 接続完了をLED_BUILTINで通知
    digitalWrite(LED_BUILTIN, HIGH);
    delay(500);
    digitalWrite(LED_BUILTIN, LOW);

    udp.begin(port);

    Serial.println("==================================");
    Serial.println(" LED遅延計測プログラム 開始");
    Serial.println(" 計測項目:");
    Serial.println("   [受信遅延] BPM受信 → LED点灯までの時間");
    Serial.println("   [周期ズレ] 期待点灯時刻 → 実際の点灯時刻のズレ");
    Serial.println("==================================");
}

void loop()
{
    // UDPでBPMを受信（4バイトfloat）
    int packetSize = udp.parsePacket();
    if (packetSize == 4) {
        float received;
        udp.read((uint8_t *)&received, sizeof(received));

        if (received > 0 && received != currentBPM) {
            receiveTime = millis(); // BPM受信時刻を記録
            currentBPM  = received;

            // 受信タイミングで期待点灯時刻をリセット
            unsigned long interval = (unsigned long)(60000.0f / currentBPM);
            expectedTime = receiveTime + interval;

            Serial.print("[BPM受信] ");
            Serial.print(currentBPM);
            Serial.print(" BPM  受信時刻: ");
            Serial.print(receiveTime);
            Serial.println(" ms");
        }
    }

    // BPMに基づいてLED点灯タイミングを制御・計測
    if (currentBPM > 0) {
        unsigned long interval = (unsigned long)(60000.0f / currentBPM);
        unsigned long now      = millis();

        if (now >= expectedTime) {
            // LED切り替え直前の時刻を記録（処理遅延を含まないように先に取得）
            unsigned long ledTime = millis();
            ledOn = !ledOn;
            analogWrite(LED_PIN, ledOn ? 255 : 0);

            if (ledOn) {
                // ① BPM受信からLED点灯までの累積遅延
                unsigned long sinceReceive = ledTime - receiveTime;
                // ② 期待点灯時刻と実際点灯時刻のズレ（ループ処理遅延）
                long jitter = (long)ledTime - (long)expectedTime;

                Serial.print("[LED点灯] ");
                Serial.print("受信遅延: ");
                Serial.print(sinceReceive);
                Serial.print(" ms  |  周期ズレ: ");
                Serial.print(jitter);
                Serial.println(" ms");
            }

            // 次の期待点灯時刻を更新（ドリフト防止のため実際の時刻ではなく期待値に加算）
            expectedTime += interval;
            prevLedTime = ledTime;
        }
    }
}
