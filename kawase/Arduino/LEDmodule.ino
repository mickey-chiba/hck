#include <Arduino.h>

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
    Serial.begin(9600);
}

void loop()
{
    // シリアルからテンポ（BPM）を受け取る
    if (Serial.available() > 0)
    {
        int received = Serial.parseInt();
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
