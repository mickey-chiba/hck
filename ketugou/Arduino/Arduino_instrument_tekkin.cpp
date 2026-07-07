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

// テンポに応じた輝度を返す（BPMが高いほど明るい）
int getBrightness(int bpm)
{
    if (bpm <= 30)
        return 0;
    else if (bpm <= 45)
        return 51;
    else if (bpm <= 60)
        return 102;
    else if (bpm <= 75)
        return 153;
    else if (bpm <= 90)
        return 204;
    else
        return 255;
}

unsigned long prevMillis = 0; // 前回のLED点滅切り替え時刻
bool ledOn = false;           // LEDのON/OFF状態
LEDmodule led1(3);            // ピン3番に接続されたLED

const char ssid[] = "Buffalo-2G-1710"; // Wi-Fiネットワークの名称
const char pass[] = "g3b5ks5tuk5fm";     // Wi-Fiのパスワード

WiFiUDP udp;

const int port = 4286; // ポート番号

float currentValue = 0.0;         // 現在のBPMを入れておく変数
float receivedValue = 0.0;        // 受信したBPMを入れておく変数
float number = 1.0;               // 輪唱の拍数を定義する変数
float preValue = 7000.0;          // BPMを受信した際の条件式に使用する変数
bool start = false;               // 開始したかを判別する変数
float musicalTime = 0;            // 音の鳴らす時間を定める時間の変数
unsigned long lastTime = 0;       // 現在時刻を保存する変数
unsigned long segmentStartMs = 0; // 現在のBPM区間が始まった絶対時刻
float segmentStartBeat = 0;       // その時点でのmusicalTime
float currentSegmentBPM = 0;      // 現在の区間のBPM
// 演奏で使う変数
const int N = 42;                  // 配列の要素数
bool noteOnSent[N] = {false};      // 発音情報を送ったか判定する配列
bool noteOffSent[N] = {false};     // 消音情報を送ったか判定する配列
bool playing = false;              // 演奏開始の合図の変数
bool processingReady = false;      // Processingの受信準備を判断する変数
bool waitingToStart = false;       // 演奏を開始することを判別する変数
float roundDelay = 0;              // 計算した輪唱時間を記録する変数
bool bpmreceivedonce = false;      // BPMが初めて届いたかのフラグ
unsigned long playbackStartMs = 0; // 演奏開始時刻
unsigned long playStartms = 0;     // 演奏開始からの時刻管理用
bool first = false;                // 配列送信完了の処理を一度だけ実行させる変数
bool experiment = true;            // BPM受信をずっと行うための変数
// 可変テンポ演奏・輪唱で使用する変数(※新規追加)
float smoothedBPM = 0;                         // 実際にmusicalTime計算で使うBPM
float bpmSmoothingFactor = 0.3;                // 0〜1で平滑化の強さ（小さいほど滑らか）
float maxBeatStepPerFrame = 0.01;              // 1フレームで進める最大拍数（要調整）
unsigned long noteOnSentAtMs[100];             // 各音符がNOTE_ONを送信した実時刻
const unsigned long MIN_NOTE_DURATION_MS = 30; // 最低30msは鳴らす
float lastDetectedBPM = -1;                    // BPM変化検出専用（currentValueとは別に持つ）
long timeOffsetMs = 0;                         // PC基準時刻 - 自分のmillis() のオフセット(ms単位)
bool timeSynced = false;
const float OFFSET_SMOOTHING = 0.05;  // 0〜1、小さいほど滑らかだが収束が遅い
float waitMusicalTime = 0;            // 待機開始からの経過拍数
float waitSegmentStartBeat = 0;       // 待機区間の開始拍
unsigned long waitSegmentStartMs = 0; // 待機区間の開始時刻
float waitLastDetectedBPM = -1;       // 一時的にBPMを保存する変数
float waitSmoothedBPM = 0;            // 平滑化
// float         noteRemainingBeats[100]; // 各音符の「残りビート数」（duration基準）
// unsigned long lastFrameMs = 0;
// 音階の配列
String noteNames[] = {"C6", "C6", "G6", "G6", "A6", "A6", "G6",
                      "F6", "F6", "E6", "E6", "D6", "D6", "C6",
                      "G6", "G6", "F6", "F6", "E6", "E6", "D6",
                      "G6", "G6", "F6", "F6", "E6", "E6", "D6",
                      "C6", "C6", "G6", "G6", "A6", "A6", "G6",
                      "F6", "F6", "E6", "E6", "D6", "D6", "C6"};
// 音を鳴らす長さの配列
float duration[] = {1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f,
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f,
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f,
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f,
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f,
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f};
// 音を鳴らす開始時間の配列
float startTime[] = {0.0f, 1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f,
                     8.0f, 9.0f, 10.0f, 11.0f, 12.0f, 13.0f, 14.0f,
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

// 未宣言エラーを防ぐための前方宣言（定義はファイル後半にある）
unsigned long syncedMillis();
void sendNoteData(int index);
void sendNoteOff(int index);

// テスト用の最小スケッチ
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

// 以後、時刻が必要な箇所はすべてこれを使う
unsigned long syncedMillis()
{
    return millis() + timeOffsetMs;
}
void updateWaitProgress(float bpm)
{
    if (bpm != waitLastDetectedBPM)
    {
        // BPM変化検出 → 区間を切り替える
        waitSegmentStartBeat = waitMusicalTime;
        waitSegmentStartMs = syncedMillis();
        waitLastDetectedBPM = bpm;
    }
    unsigned long timeMs = syncedMillis() - waitSegmentStartMs;
    float timeSeconds = timeMs / 1000.0;
    waitMusicalTime = waitSegmentStartBeat + timeSeconds * (bpm / 60.0);
}

void sendNoteData(int index)
{
    Serial.write(0xAA);
    Serial.write(0x55);
    Serial.write(index);

    // 音符名（可変長：長さ＋本体）
    uint8_t nameLen = (uint8_t)noteNames[index].length();
    Serial.write(nameLen);
    Serial.write(noteNames[index].c_str(), nameLen);
    // Serial.write((uint8_t)1);
    // 音量（固定4バイト）
    uint8_t *p = (uint8_t *)&amplitudes[index];
    Serial.write(p, sizeof(float));

    Serial.flush();
}

void sendNoteOff(int index)
{
    Serial.write(0xCC);           // スタートヘッダー1
    Serial.write(0x33);           // スタートヘッダー2
    Serial.write((uint8_t)index); // 配列番号を1バイトに変換して送信
    // Serial.write((uint8_t)0);     //0を送信する
    Serial.flush();
}

void writeFloatValue(float val)
{
    uint8_t *p = (uint8_t *)&val;   // valをuint8_tに変換
    Serial.write(p, sizeof(float)); // 変換したバイナリ型の値とサイズ数を送信
    Serial.flush();
}

void sendtempo(float val)
{                         // BPMをシリアル通信する関数
    Serial.write(0xBB);   // スタートヘッダー1
    Serial.write(0x66);   // スタートヘッダー2
    writeFloatValue(val); // 関数を用いてBPMを送信する
}

void updateSmoothedBPM(float targetBPM)
{
    if (smoothedBPM <= 0)
    {
        smoothedBPM = targetBPM; // 初回はそのまま代入
    }
    else
    {
        // 線形補間で滑らかに近づける（急激なジャンプを防ぐ）
        smoothedBPM += (targetBPM - smoothedBPM) * bpmSmoothingFactor;
    }
}
void BPMchanged(float newBPM)
{
    // 現在のmusicalTimeを「区間の開始点」として固定する
    segmentStartBeat = musicalTime;
    segmentStartMs = syncedMillis();
    currentSegmentBPM = newBPM;
}
void melospeed(float bpm)
{ // メロディーの時間を計算して進める関数
    updateSmoothedBPM(bpm);
    if (bpm != lastDetectedBPM)
    {
        BPMchanged(bpm);
        lastDetectedBPM = bpm; // ここで更新するのを忘れない
    }
    unsigned long timeMs = syncedMillis() - segmentStartMs;                   // 開始から何秒経過したかを計算する
    float timeSeconds = timeMs / 1000.0;                                      // 前回のループからの経過時間を計算し秒数に変換
    float targetTime = segmentStartBeat + timeSeconds * (smoothedBPM / 60.0); // 経過した時間を足す(受信したテンポによって時間を大きくする)
    float step = targetTime - musicalTime;
    if (step > maxBeatStepPerFrame)
    {
        step = maxBeatStepPerFrame; // 進みすぎを抑える
    }
    else if (step < 0)
    {
        step = 0; // 後退はさせない
    }

    musicalTime += step;
}

void updateNotes()
{
    for (int i = 0; i < N; i++)
    {
        if (!noteOnSent[i] && musicalTime >= startTime[i])
        {                                       // 発音していないかつ音を鳴らす時間まで時間が経過したら実行する
            sendNoteData(i);                    // 発音情報を送信する
            noteOnSent[i] = true;               // 配列をtrueにする
            noteOnSentAtMs[i] = syncedMillis(); // ON送信時刻を記録
                                                // noteRemainingBeats[i]  = duration[i]; // ★初期値はduration[i]（ビート数）
                                                // Serial.print("NOTE_ON送信 i="); Serial.println(i); // デバッグ
        }
        if (noteOnSent[i] && !noteOffSent[i] && musicalTime >= startTime[i] + duration[i])
        {
            unsigned long elapsedSinceOn = syncedMillis() - noteOnSentAtMs[i];
            if (elapsedSinceOn < MIN_NOTE_DURATION_MS)
            {
                continue; // まだ最小時間に達していないのでOFFを送らず次のフレームへ
            }
            sendNoteOff(i);        // 消音情報を送信する
            noteOffSent[i] = true; // 消音情報を管理する配列をtrueにする
            // Serial.print("NOTE_OFF送信 i="); Serial.println(i); // デバッグ
        }
        // if (noteOnSent[i] && !noteOffSent[i] && noteRemainingBeats[i] <= 0) {
        //   sendNoteOff(i);
        //   noteOffSent[i] = true;
        // }
    }
}

void resetPlayback()
{ // 前回までの情報をリセットする関数
    musicalTime = 0;
    playbackStartMs = millis();
    // lastFrameMs    = syncedMillis(); // lastTimeから変更（変数名を統一）
    playing = false;
    preValue = -1;
    waitingToStart = false;
    bpmreceivedonce = false;
    playStartms = 0;
    segmentStartMs = syncedMillis();
    segmentStartBeat = 0;
    waitMusicalTime = 0;
    waitSegmentStartBeat = 0;
    waitSegmentStartMs = millis();
    waitLastDetectedBPM = -1;

    // 全音符のON/OFFフラグをリセット
    for (int i = 0; i < N; i++)
    {
        noteOnSent[i] = false;
        noteOffSent[i] = false;
    }
}
int syncCount = 0;
const int SYNC_COUNT_REQUIRED = 20;
void handleTimeSync(int64_t pcTimeUs)
{
    // PC側はマイクロ秒、Arduino側はミリ秒で扱うので変換する
    int64_t pcTimeMs = pcTimeUs / 1000;

    unsigned long myMillis = millis();
    long newOffset = (long)(pcTimeMs - (int64_t)myMillis);

    if (!timeSynced)
    {
        timeOffsetMs = newOffset;
        timeSynced = true;
    }
    else
    {
        // 複数回の同期パケットで少しずつ収束させ、1回ごとのジッタの影響を抑える
        timeOffsetMs += (long)((newOffset - timeOffsetMs) * OFFSET_SMOOTHING);
    }
    // syncCount++;
}

void loop()
{
    if (Serial.available() > 0)
    {
        int signal = Serial.read(); // 受信したシリアルデータを読み、signalに代入

        if (signal == 0xDD && !processingReady)
        { // 送信されたデータが0xFFかつprocessingReady = falseの時に実行
            // 配列データ送信済み、READY信号を待っている段階
            resetPlayback(); // 情報をリセットする関数を呼び出す
            processingReady = true;
            bpmreceivedonce = false;
            roundDelay = 0;
            playStartms = 0;
            waitingToStart = true;
        }
    }
    if (experiment)
    {
        int packetSize = udp.parsePacket(); // パケットの処理を開始する
        if (packetSize == 12)
        {
            uint8_t buf[12];
            udp.read(buf, 12);
            int32_t marker;
            int64_t pcTimeUs;
            memcpy(&marker, buf, 4);
            memcpy(&pcTimeUs, buf + 4, 8);

            if (marker == -1)
            {
                handleTimeSync(pcTimeUs);
            }
        }
        else if (packetSize == 4)
        {
            float receivedValue;
            udp.read((uint8_t *)&receivedValue, sizeof(receivedValue)); //
            if (receivedValue != preValue)
            {

                currentValue = receivedValue;
                preValue = receivedValue;
                Serial.print("BPM = ");
                Serial.println(currentValue);
                sendtempo(currentValue); // 関数を呼び出しBPMをシリアル送信
                // digitalWrite(LED_BUILTIN, HIGH);
                // delay(2000);
                // digitalWrite(LED_BUILTIN, LOW);

                if (waitingToStart && !bpmreceivedonce)
                {
                    bpmreceivedonce = true;
                    // 待機拍数の追跡を開始する
                    waitMusicalTime = 0;
                    waitSegmentStartBeat = 0;
                    waitSegmentStartMs = syncedMillis();
                    waitLastDetectedBPM = currentValue;
                }
            }

            else
            {
                // 想定外のサイズのデータが来た場合は読み飛ばしてバッファをクリア
                udp.flush();
                // Serial.println("エラー: 4バイト以外のデータを受信しました");
            }
        }
    }
    if (waitingToStart && bpmreceivedonce)
    { // 配列データの送信完了かつBPM送信かつ輪唱時間以上になったら実行
        updateWaitProgress(currentValue);
        if (number <= 0 || waitMusicalTime >= number)
        {
            waitingToStart = false; // falseにする(1度だけ実行するため)
            playing = true;
            segmentStartMs = syncedMillis();
            segmentStartBeat = 0;
            musicalTime = 0;
            currentSegmentBPM = currentValue;
            lastDetectedBPM = currentValue; // 追加：BPM変化検出の基準もここで揃える
        }
    }
    if (playing && processingReady)
    {                            // 輪唱が終わったかつ配列の受信が終わったら実行
        melospeed(currentValue); // musicalTimeを毎回進める
        updateNotes();           // 音符タイミングを毎回判定する
        // digitalWrite(LED_BUILTIN, HIGH);
        // delay(10);
        // digitalWrite(LED_BUILTIN, LOW);
    }

    // BPM同期LED点滅（currentValueが有効な値のときだけ動作）
    if (currentValue > 0)
    {
        // BPMから1拍あたりの間隔（ms）を計算: 60000ms ÷ BPM
        unsigned long interval = (unsigned long)(60000.0f / currentValue);
        unsigned long now = millis();
        if (now - prevMillis >= interval)
        {
            prevMillis = now;
            // LEDのON/OFFをトグル（切り替え）する
            ledOn = !ledOn;
            led1.setBrightness(ledOn ? getBrightness((int)currentValue) : 0);
        }
    }
}
