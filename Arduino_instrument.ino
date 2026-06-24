#include <WiFiS3.h>
#include <WiFiUdp.h>

const char ssid[] = "WiFi_bro_colstra";   //Wi-Fiネットワークの名称
const char pass[] = "wf215nt109rt";       //Wi-Fiのパスワード

WiFiUDP udp;

const int port = 4286;                    //ポート番号

float currentValue = 0.0;                 //現在のBPMを入れておく変数
float receivedValue = 0.0;                //受信したBPMを入れておく変数
float number = 1.0;                       //輪唱の拍数を定義する変数
float preValue = 7000.0;                  //BPMを受信した際の条件式に使用する変数
bool roundMode = false;
bool start = false;                       //開始したかを判別する変数
//可変テンポ演奏で使う変数
float musicalTime = 0;                     //音の鳴らす時間を定める時間の変数
unsigned long lastTime = 0;                //現在時刻を保存する変数
const int N = 42;                          //配列の要素数
bool          noteOnSent[N]  = {false};    //発音情報を送ったか判定する配列
bool          noteOffSent[N] = {false};    //消音情報を送ったか判定する配列
bool          playing         = false;     //演奏開始の合図の変数
bool          processingReady = false;     //Processingの受信準備を判断する変数
unsigned long playStartms    = 0;          //輪唱までの時間を記録する変数
bool          waitingToStart = false;      //演奏を開始することを判別する変数
float         roundDelay     = 0;          //計算した輪唱時間を記録する変数
bool          bpmreceivedonce = false;     // BPMが初めて届いたかのフラグ
bool first = false;                        //配列送信完了の処理を一度だけ実行させる変数
bool experiment = true;                    //BPM受信をずっと行うための変数
//音階の配列
String noteNames[] = {"C4", "C4", "G4", "G4", "A4", "A4", "G4",
                      "F4", "F4", "E4", "E4", "D4", "D4", "C4",
                      "G4", "G4", "F4", "F4", "E4", "E4", "D4",
                      "G4", "G4", "F4", "F4", "E4", "E4", "D4",
                      "C4", "C4", "G4", "G4", "A4", "A4", "G4",
                      "F4", "F4", "E4", "E4", "D4", "D4", "C4"};
//音を鳴らす長さの配列
float duration[] = {1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f, 
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f, 
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f, 
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f,
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f, 
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f};
//音を鳴らす開始時間の配列
float startTime[] = {0.0f, 1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f, 
                    8.0f, 9.0f, 10.0f, 11.0f, 12.0f, 13.0f, 14.0f, 
                    16.0f, 17.0f, 18.0f, 19.0f, 20.0f, 21.0f, 22.0f,
                    24.0f, 25.0f, 26.0f, 27.0f, 28.0f, 29.0f, 30.0f,
                    32.0f, 33.0f, 34.0f, 35.0f, 36.0f, 37.0f, 38.0f,
                    40.0f, 41.0f, 42.0f, 43.0f, 44.0f, 45.0f, 46.0f};
//音の大きさの配列
float amplitudes[] = {0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.6f,
                      0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.7f, 
                      0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.8f,
                      0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.9f,
                      0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.8f,
                      0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.9f};

// テスト用の最小スケッチ 
void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);

  while (WiFi.begin(ssid, pass) != WL_CONNECTED) {      //ネットワークに接続されたか確認する処理
    delay(1000);
  }
  delay(1000);
    digitalWrite(LED_BUILTIN, HIGH);
    delay(1000);
    digitalWrite(LED_BUILTIN, LOW);

  udp.begin(port);                                       //UDPソケットを開始
}

void writeFloatArray(float* arr, int n) {             //float配列の先頭アドレス、nは要素数
  uint8_t* p = (uint8_t*)arr;                         //floatポインタをuint8_tに変換
  int totalBytes = n * sizeof(float);                 //総バイト数を計算
  int offset = 0;                                     //どこまで送るかを記録する変数
  
  while (offset < totalBytes) {                        //総バイト数までループ
    int chunk = min(64, totalBytes - offset);          //送るバイト数を決める。64バイト比較する
    Serial.write(p + offset, chunk);                   //ポインタ演算した値とバイト数を送信
    Serial.flush();                                    // チャンクごとにflush
    offset += chunk;                                   //読み取ったバイト数をoffsetにプラスする
  }
}
//float配列の処理
void writeFloatValue(float val) {
  uint8_t* p = (uint8_t*)&val;              //valをuint8_tに変換
  Serial.write(p, sizeof(float));           //変換したバイナリ型の値とサイズ数を送信
  Serial.flush();
}
//String配列の処理
void writeStringArray(String* arr, int n) {
  for (int i = 0; i < n; i++) {
    uint8_t len = (uint8_t)arr[i].length();   //文字列の長さを1バイトにする   
    Serial.write(len);                        //文字列の長さを送信する
    Serial.flush();                           //送信が完了するまで待つ
    Serial.write((uint8_t*)arr[i].c_str(), len);    //配列をchar型にして1バイトのバッファと配列の大きさを送信
    Serial.flush();
  }
}
void sendtempo(float val) {      //BPMをシリアル通信する関数
  Serial.write(0xBB);     //スタートヘッダー1
  Serial.write(0x66);     //スタートヘッダー2
  writeFloatValue(val);   //関数を用いてBPMを送信する
}
void sendmeloinf(){      //音階データの送信
  Serial.write(0xAA); // スタートヘッダー1
  Serial.write(0x55); // スタートヘッダー2
  uint16_t datasize = sizeof(duration) / sizeof(duration[0]); // 配列の要素数を計算
  Serial.write((uint8_t)datasize); // 要素数をuint8_t(1バイト)にキャスト
  writeStringArray(noteNames, datasize);
  writeFloatArray(amplitudes,  datasize);
  
 
}
void melospeed(float receivedValue) {     //メロディーの時間を計算して進める関数
  unsigned long now          = millis();    //現時刻を記録
  float         deltaSeconds = (now - lastTime) / 1000.0;   //前回のループからの経過時間を計算し秒数に変換
  lastTime = now;             //lastTimeにnowを代入する
  musicalTime += deltaSeconds * (receivedValue / 80.0);   //経過した時間を足す(受信したテンポによって時間を大きくする)
}

void updateNotes() {
  for (int i = 0; i < N; i++) {
    if (!noteOnSent[i] && musicalTime >= startTime[i]) {    //発音していないかつ音を鳴らす時間まで時間が経過したら実行する
      sendNoteOn(i);                                        //発音情報を送信する
      noteOnSent[i] = true;                                 //配列をtrueにする
      // Serial.print("NOTE_ON送信 i="); Serial.println(i); // デバッグ
    }
    if (noteOnSent[i] && !noteOffSent[i]
        && musicalTime >= startTime[i] + duration[i]) {
      sendNoteOff(i);                                       //消音情報を送信する
      noteOffSent[i] = true;                                //消音情報を管理する配列をtrueにする
      // Serial.print("NOTE_OFF送信 i="); Serial.println(i); // デバッグ
    }
  }
}

void sendNoteOn(int index) {
  Serial.write(0xCC);           //スタートヘッダー1 
  Serial.write(0x33);           //スタートヘッダー2
  Serial.write((uint8_t)index); //配列の番号を1バイトに変換して送信
  Serial.write((uint8_t)1);     //1を送信する
  Serial.flush();
}

void sendNoteOff(int index) {
  Serial.write(0xCC);           //スタートヘッダー1
  Serial.write(0x33);           //スタートヘッダー2
  Serial.write((uint8_t)index); //配列番号を1バイトに変換して送信
  Serial.write((uint8_t)0);     //0を送信する
  Serial.flush();
}
void resetPlayback() {    //前回までの情報をリセットする関数
  musicalTime    = 0;
  lastTime       = millis();
  playing        = false;
  preValue       = -1;      
  waitingToStart = false;
  bpmreceivedonce = false;  
  playStartms    = 0;      

  // 全音符のON/OFFフラグをリセット
  for (int i = 0; i < N; i++) {
    noteOnSent[i]  = false;
    noteOffSent[i] = false;
  }
}
void loop() {
  if (Serial.available() > 0) {
    int signal = Serial.read();   //受信したシリアルデータを読み、signalに代入
    digitalWrite(LED_BUILTIN, HIGH); // 何か受信したら点灯
    delay(200);
    digitalWrite(LED_BUILTIN, LOW);
    if(!first){
      if(signal == 0xDD && !start){   //送信されたデータが0xDDかつstart = falseの時に実行
        start = true;
        roundMode = true;
        first = true; 
        sendmeloinf();            //配列を送信する関数を呼び出す
        // digitalWrite(LED_BUILTIN, HIGH); // 何か受信したら点灯
        // delay(100);
        // digitalWrite(LED_BUILTIN, LOW);    
      // sendmeloinf() はまだ呼ばない（最小限の確認のため）
      }
    }else if (!processingReady) {   //送信されたデータが0xFFかつprocessingReady = falseの時に実行
      // 配列データ送信済み、READY信号を待っている段階
      if (signal == 0xFF) {   
        resetPlayback();      //情報をリセットする関数を呼び出す
        processingReady = true;
        bpmreceivedonce = false;
        roundDelay = 0;
        playStartms = 0;
        waitingToStart = true;
        // digitalWrite(LED_BUILTIN, HIGH); // 何か受信したら点灯
        // delay(2000);
        // digitalWrite(LED_BUILTIN, LOW);    
      }
    }
  }
  if(experiment){ 
    int packetSize = udp.parsePacket();     //パケットの処理を開始する
      if (packetSize == 4) {
        float receivedValue;
        udp.read((uint8_t*)&receivedValue, sizeof(receivedValue));    //
        if (receivedValue != preValue) {

          currentValue = receivedValue;
          preValue = receivedValue;
          // Serial.print("BPM = ");
          // Serial.println(currentValue);
          sendtempo(currentValue);                          //関数を呼び出しBPMをシリアル送信
          // digitalWrite(LED_BUILTIN, HIGH); 
          // delay(2000);
          // digitalWrite(LED_BUILTIN, LOW);
    
          if(waitingToStart && !bpmreceivedonce){
            bpmreceivedonce = true;
            if(number > 0){
              float beatduration = 60000.0 / currentValue;      //ms単位でBPMを基に1泊の長さを計算
              roundDelay = beatduration * number;               //拍数を基に輪唱する時間を計算する
            } else{
              roundDelay = 0;
            }
            playStartms = millis() + (unsigned long)roundDelay; //現時刻 + 輪唱する時間
          }
        }else {
        // 想定外のサイズのデータが来た場合は読み飛ばしてバッファをクリア
          udp.flush();
          // Serial.println("エラー: 4バイト以外のデータを受信しました");
        }
      }
    }

  if (waitingToStart && bpmreceivedonce && millis() >= playStartms) {   //配列データの送信完了かつBPM送信かつ輪唱時間以上になったら実行
    if(currentValue > 0){
      waitingToStart = false;       //falseにする(1度だけ実行するため)
      playing        = true;
      lastTime       = millis();
      // for(int i=0; i<2; i++){
      //   digitalWrite(LED_BUILTIN, HIGH);
      //   delay(100);
      //   digitalWrite(LED_BUILTIN, LOW);
      //   delay(100);
      // }
    }
  }
  if (playing && processingReady) {     //輪唱が終わったかつ配列の受信が終わったら実行
      melospeed(currentValue); // musicalTimeを毎回進める
      updateNotes();           // 音符タイミングを毎回判定する
      // digitalWrite(LED_BUILTIN, HIGH);
      // delay(10);
      // digitalWrite(LED_BUILTIN, LOW);

  } 

}

