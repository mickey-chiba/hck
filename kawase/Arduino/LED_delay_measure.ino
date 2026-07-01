#include <WiFiS3.h>
#include <WiFiUdp.h>

const char ssid[] = "WiFi_bro_colstra"; // Wi-Fiネットワークの名称
const char pass[] = "wf215nt109rt";     // Wi-Fiのパスワード

WiFiUDP udp;

const int port = 4286; // ポート番号

float currentValue    = 0.0;    // 現在のBPMを入れておく変数
float receivedValue   = 0.0;    // 受信したBPMを入れておく変数
float number          = 1.0;    // 輪唱の拍数を定義する変数
float preValue        = 7000.0; // BPMを受信した際の条件式に使用する変数
bool  roundMode       = false;
bool  start           = false;  // 開始したかを判別する変数

// 可変テンポ演奏で使う変数
float         musicalTime     = 0;       // 音の鳴らす時間を定める時間の変数
unsigned long lastTime        = 0;       // 現在時刻を保存する変数
const int     N               = 42;      // 配列の要素数
bool          noteOnSent[N]   = {false}; // 発音情報を送ったか判定する配列
bool          noteOffSent[N]  = {false}; // 消音情報を送ったか判定する配列
bool          playing         = false;   // 演奏開始の合図の変数
bool          processingReady = false;   // Processingの受信準備を判断する変数
unsigned long playStartms     = 0;       // 輪唱までの時間を記録する変数
bool          waitingToStart  = false;   // 演奏を開始することを判別する変数
float         roundDelay      = 0;       // 計算した輪唱時間を記録する変数
bool          bpmreceivedonce = false;   // BPMが初めて届いたかのフラグ
bool          first           = false;   // 配列送信完了の処理を一度だけ実行させる変数
bool          experiment      = true;    // BPM受信をずっと行うための変数

// 音階の配列
String noteNames[] = {"C4", "C4", "G4", "G4", "A4", "A4", "G4",
                      "F4", "F4", "E4", "E4", "D4", "D4", "C4",
                      "G4", "G4", "F4", "F4", "E4", "E4", "D4",
                      "G4", "G4", "F4", "F4", "E4", "E4", "D4",
                      "C4", "C4", "G4", "G4", "A4", "A4", "G4",
                      "F4", "F4", "E4", "E4", "D4", "D4", "C4"};
// 音を鳴らす長さの配列
float duration[] = {1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f,
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f,
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f,
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f,
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f,
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f};
// 音を鳴らす開始時間の配列
float startTime[] = {0.0f,  1.0f,  2.0f,  3.0f,  4.0f,  5.0f,  6.0f,
                     8.0f,  9.0f,  10.0f, 11.0f, 12.0f, 13.0f, 14.0f,
                     16.0f, 17.0f, 18.0f, 19.0f, 20.0f, 21.0f, 22.0f,
                     24.0f, 25.0f, 26.0f, 27.0f, 28.0f, 29.0f, 30.0f,
                     32.0f, 33.0f, 34.0f, 35.0f, 36.0f, 37.0f, 38.0f,
                     40.0f, 41.0f, 42.0f, 43.0f, 44.0f, 45.0f, 46.0f};
// 音の大きさの配列
float amplitudes[] = {0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.6f,
                      0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.7f,
                      0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.8f,
                      0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.9f,
                      0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.8f,
                      0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.9f};

// LEDを制御するクラス
class LEDmodule
{
private:
    int _pin; // LEDのピン番号
    int _bri; // 現在の輝度

public:
    LEDmodule(int pin) : _pin(pin), _bri(0) {}

    void setBrightness(int bri)
    {
        _bri = bri;
        analogWrite(_pin, _bri); // PWMで輝度を設定する
    }
};

int count = 0;
LEDmodule led1(3); // ピン3に接続したLEDモジュール

// 遅延計測用変数
unsigned long receiveTime  = 0;     // BPM受信時刻（ms）
unsigned long expectedTime = 0;     // 次の期待点灯時刻（ms）
bool          ledOn        = false; // LED点灯状態

void setup()
{
    Serial.begin(115200);
    pinMode(LED_BUILTIN, OUTPUT);

    // Wi-Fiに接続できるまでリトライする
    while (WiFi.begin(ssid, pass) != WL_CONNECTED)
    {
        delay(1000);
    }
    delay(1000);
    // 接続完了をLED_BUILTINの点滅で通知する
    digitalWrite(LED_BUILTIN, HIGH);
    delay(1000);
    digitalWrite(LED_BUILTIN, LOW);

    udp.begin(port); // UDPソケットを開始する

    Serial.println("==================================");
    Serial.println(" LED遅延計測プログラム 開始");
    Serial.println(" 計測項目:");
    Serial.println("   [遅延] BPM受信 -> LED点灯のズレ（ms）");
    Serial.println("==================================");
}

// float配列をチャンク分割してシリアル送信する
void writeFloatArray(float *arr, int n)
{
    uint8_t *p          = (uint8_t *)arr;    // floatポインタをuint8_tに変換する
    int      totalBytes = n * sizeof(float); // 総バイト数を計算する
    int      offset     = 0;                 // 送信済みバイト数を追跡する変数

    while (offset < totalBytes)
    {
        int chunk = min(64, totalBytes - offset); // 最大64バイトずつ送信する
        Serial.write(p + offset, chunk);          // ポインタ演算で対象バイトを送信する
        Serial.flush();
        offset += chunk;
    }
}

// float値をバイナリでシリアル送信する
void writeFloatValue(float val)
{
    uint8_t *p = (uint8_t *)&val;  // valのメモリをuint8_t列として扱う
    Serial.write(p, sizeof(float));
    Serial.flush();
}

// String配列を長さプレフィックス付きでシリアル送信する
void writeStringArray(String *arr, int n)
{
    for (int i = 0; i < n; i++)
    {
        uint8_t len = (uint8_t)arr[i].length();       // 文字列長を1バイトに収める
        Serial.write(len);
        Serial.flush();
        Serial.write((uint8_t *)arr[i].c_str(), len); // 文字列本体を送信する
        Serial.flush();
    }
}

// BPMをシリアル送信する（ヘッダー: 0xBB 0x66）
void sendtempo(float val)
{
    Serial.write(0xBB);
    Serial.write(0x66);
    writeFloatValue(val);
}

// 音階データをシリアル送信する（ヘッダー: 0xAA 0x55）
void sendmeloinf()
{
    Serial.write(0xAA);
    Serial.write(0x55);
    uint16_t datasize = sizeof(duration) / sizeof(duration[0]); // 配列の要素数を計算する
    Serial.write((uint8_t)datasize);
    writeStringArray(noteNames, datasize);
    writeFloatArray(amplitudes, datasize);
}

// BPMに応じて音楽時間を進める
void melospeed(float bpm)
{
    unsigned long now          = millis();
    float         deltaSeconds = (now - lastTime) / 1000.0; // 前回ループからの経過秒数
    lastTime                   = now;
    musicalTime += deltaSeconds * (bpm / 80.0); // 基準BPM=80として時間を伸縮させる
}

// 発音情報をシリアル送信する（ヘッダー: 0xCC 0x33 + index + 1）
void sendNoteOn(int index)
{
    Serial.write(0xCC);
    Serial.write(0x33);
    Serial.write((uint8_t)index);
    Serial.write((uint8_t)1);
    Serial.flush();
}

// 消音情報をシリアル送信する（ヘッダー: 0xCC 0x33 + index + 0）
void sendNoteOff(int index)
{
    Serial.write(0xCC);
    Serial.write(0x33);
    Serial.write((uint8_t)index);
    Serial.write((uint8_t)0);
    Serial.flush();
}

// musicalTimeに基づいて発音・消音のタイミングを判定する
void updateNotes()
{
    for (int i = 0; i < N; i++)
    {
        if (!noteOnSent[i] && musicalTime >= startTime[i])
        {
            sendNoteOn(i);
            noteOnSent[i] = true;
        }
        if (noteOnSent[i] && !noteOffSent[i] && musicalTime >= startTime[i] + duration[i])
        {
            sendNoteOff(i);
            noteOffSent[i] = true;
        }
    }
}

// 演奏に関わる全状態をリセットする
void resetPlayback()
{
    musicalTime     = 0;
    lastTime        = millis();
    playing         = false;
    preValue        = -1;
    waitingToStart  = false;
    bpmreceivedonce = false;
    playStartms     = 0;

    for (int i = 0; i < N; i++)
    {
        noteOnSent[i]  = false;
        noteOffSent[i] = false;
    }
}

void loop()
{
    // シリアルからProcessingの制御信号を受信する
    if (Serial.available() > 0)
    {
        int signal = Serial.read();
        digitalWrite(LED_BUILTIN, HIGH); // 受信確認のためLEDを点灯する
        delay(200);
        digitalWrite(LED_BUILTIN, LOW);

        if (!first)
        {
            // 0xDDを受信したら音階データを送信して演奏準備を開始する
            if (signal == 0xDD && !start)
            {
                start     = true;
                roundMode = true;
                first     = true;
                sendmeloinf();
            }
        }
        else if (!processingReady)
        {
            // 0xFFを受信したらProcessingの受信準備完了とみなす
            if (signal == 0xFF)
            {
                resetPlayback();
                processingReady = true;
                bpmreceivedonce = false;
                roundDelay      = 0;
                playStartms     = 0;
                waitingToStart  = true;
            }
        }
    }

    // UDPでBPMを受信する（4バイトfloat）
    if (experiment)
    {
        int packetSize = udp.parsePacket();
        if (packetSize == 4)
        {
            float receivedValue;
            udp.read((uint8_t *)&receivedValue, sizeof(receivedValue));

            if (receivedValue != preValue)
            {
                currentValue = receivedValue;
                preValue     = receivedValue;
                Serial.print("BPM = ");
                Serial.println(currentValue);
                sendtempo(currentValue); // BPMをProcessingへ転送する

                // BPM受信時刻と次の期待点灯時刻を記録する
                receiveTime               = millis();
                unsigned long interval_ms = (unsigned long)(60000.0f / currentValue);
                expectedTime              = receiveTime + interval_ms;

                // 輪唱開始タイミングを計算する（初回BPM受信時のみ）
                if (waitingToStart && !bpmreceivedonce)
                {
                    bpmreceivedonce = true;
                    if (number > 0)
                    {
                        float beatduration = 60000.0 / currentValue; // 1拍の長さ（ms）
                        roundDelay         = beatduration * number;   // 輪唱ディレイ（ms）
                    }
                    else
                    {
                        roundDelay = 0;
                    }
                    playStartms = millis() + (unsigned long)roundDelay;
                }
            }
            else
            {
                udp.flush(); // 4バイト以外のデータは読み飛ばしてバッファをクリアする
            }
        }
    }

    // 輪唱ディレイ経過後に演奏を開始する
    if (waitingToStart && bpmreceivedonce && millis() >= playStartms)
    {
        if (currentValue > 0)
        {
            waitingToStart = false; // 二重起動を防ぐためfalseにする
            playing        = true;
            lastTime       = millis();
        }
    }

    // 演奏中は音符タイミングを毎ループ判定する
    if (playing && processingReady)
    {
        melospeed(currentValue);
        updateNotes();
    }

    // バグ修正: 現在時刻で初期化することで正しく1秒待機する
    unsigned long millis_buf = millis();
    while ((millis() - millis_buf) < 1000)
    {
        ;
    }

    count++;

    // BPM範囲に応じてLEDの輝度を切り替える
    if (currentValue <= 30)
    {
        if ((count % 50) == 0)
        {
            led1.setBrightness(0);
        }
    }
    else if (30 < currentValue && currentValue <= 45)
    {
        if ((count % 50) == 0)
        {
            led1.setBrightness(51);
            if ((count % 100) == 0)
            {
                led1.setBrightness(0);
            }
        }
    }
    else if (45 < currentValue && currentValue <= 60)
    {
        if ((count % 50) == 0)
        {
            led1.setBrightness(102);
            if ((count % 100) == 0)
            {
                led1.setBrightness(0);
            }
        }
    }
    else if (60 < currentValue && currentValue <= 75)
    {
        if ((count % 50) == 0)
        {
            led1.setBrightness(153);
            if ((count % 100) == 0)
            {
                led1.setBrightness(0);
            }
        }
    }
    else if (75 < currentValue && currentValue <= 90)
    {
        if ((count % 50) == 0)
        {
            led1.setBrightness(204);
            if ((count % 100) == 0)
            {
                led1.setBrightness(0);
            }
        }
    }
    else if (90 < currentValue && currentValue <= 120)
    {
        if ((count % 50) == 0)
        {
            led1.setBrightness(255);
            if ((count % 100) == 0)
            {
                led1.setBrightness(255);
            }
        }
    }

    // BPMに合わせてLEDを点灯し、今回の遅延（ズレ）だけを計測する
    if (currentValue > 0)
    {
        unsigned long interval_ms = (unsigned long)(60000.0f / currentValue);
        unsigned long now         = millis();

        if (now >= expectedTime)
        {
            unsigned long ledTime = millis();
            ledOn = !ledOn;
            led1.setBrightness(ledOn ? 255 : 0);

            if (ledOn)
            {
                // 期待点灯時刻と実際の点灯時刻のズレ（今回の遅延のみ）
                long jitter = (long)ledTime - (long)expectedTime;
                Serial.print("[遅延] ");
                Serial.print(jitter);
                Serial.println(" ms");
            }

            // ドリフト防止のため実際の時刻ではなく期待値に加算する
            expectedTime += interval_ms;
        }
    }
}
