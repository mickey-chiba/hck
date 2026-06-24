#include <Arduino.h>
#include <WiFiS3.h>
#include <WiFiUdp.h>

// LEDを制御するクラス（PWM制御でピンに接続されたLEDの明るさを管理）
class LEDmodule
{
private:
    int _pin;
    int _bri;

public:
    // コンストラクタ: ピン番号を受け取り、輝度を0で初期化
    LEDmodule(int pin) : _pin(pin), _bri(0) {}

    // 輝度を0〜255の範囲で設定し、PWM出力する
    void setBrightness(int bri)
    {
        _bri = bri;
        analogWrite(_pin, _bri);
    }
};

int tempo = 120;              // テンポ（BPM）の初期値
unsigned long prevMillis = 0; // 前回の点滅切り替え時刻（グローバルで保持）
bool ledOn = false;           // LEDのON/OFF状態

LEDmodule led1(3);

const char ssid[] = "WiFi_bro_colstra"; // Wi-Fiネットワークの名称
const char pass[] = "wf215nt109rt";     // Wi-Fiのパスワード

WiFiUDP udp;

const int port = 4286; // ポート番号

// テンポに応じた輝度を返す（BPMが高いほど明るい）
int getBrightness(int bpm)
{
    if (bpm <= 30)       return 0;
    else if (bpm <= 45)  return 51;
    else if (bpm <= 60)  return 102;
    else if (bpm <= 75)  return 153;
    else if (bpm <= 90)  return 204;
    else                 return 255;
}

void setup()
{
    Serial.begin(115200);
    pinMode(LED_BUILTIN, OUTPUT);

    while (WiFi.begin(ssid, pass) != WL_CONNECTED)
    { // ネットワークに接続されたか確認する処理
        delay(1000);
    }
    delay(1000);
    digitalWrite(LED_BUILTIN, HIGH);
    delay(1000);
    digitalWrite(LED_BUILTIN, LOW);

    udp.begin(port); // UDPソケットを開始
}

void loop()
{
    // UDPパケットが届いていたらテンポ（BPM）を受け取る
    int packetSize = udp.parsePacket();
    if (packetSize > 0)
    {
        char buf[8] = {0};
        udp.read(buf, sizeof(buf) - 1); // パケットを読み取る
        int received = atoi(buf);       // 文字列を整数に変換
        if (received > 0)
        {
            tempo = received;
            Serial.print("テンポ受信: ");
            Serial.println(tempo);
        }
    }

    // BPMから1拍あたりの間隔（ms）を計算: 60000ms ÷ BPM
    unsigned long interval = 60000UL / (unsigned long)tempo;

    unsigned long now = millis();
    // 前回の切り替えから interval ms 経過していたら点滅トグル
    if (now - prevMillis >= interval)
    {
        prevMillis = now;

        // LEDのON/OFFをトグル（切り替え）する
        ledOn = !ledOn;
        if (ledOn)
        {
            led1.setBrightness(getBrightness(tempo));
        }
        else
        {
            led1.setBrightness(0);
        }
    }
}
