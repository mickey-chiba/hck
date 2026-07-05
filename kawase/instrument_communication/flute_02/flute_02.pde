// flute_02.pde
// flute_communication.pde に LED_delay_measure.pde（Processing版遅延計測）を結合したスケッチ。
// Arduino からシリアルで BPM・音階データ・発音イベントを受信して演奏しつつ、
// BPM から計算した期待点灯時刻と実際の点灯処理時刻のズレ（遅延）を計測・表示する。
//
// 結合元:
//   - flute_communication.pde : シリアル受信（0xAA/0xBB/0xCC ヘッダー）と minim での発音
//   - LED_delay_measure.pde   : 遅延計測ロジック（期待点灯時刻とのズレ計測）

import ddf.minim.*;
import ddf.minim.ugens.*;
import processing.serial.*;
import java.nio.*;

Serial myPort;
float tempo = 0.0;
int N;
float updatedtempo = 0.0;
AudioOutput out;
Minim minim;
InstrumentModule flute;

String[] melody;

float[] duration;
float[] startTime;
float[] amplitudes;

boolean dataLoaded = false;
// テンポ管理
float   currentBPM = 0;

// musicalTime管理
boolean   playing     = false;
float     musicalTime = 0;
long      lastTimeMs  = 0;
boolean[] noteStarted;

// 遅延計測用変数（LED_delay_measure.pde から結合）
long    receiveTime  = 0;     // BPM受信時刻（ms）
long    expectedTime = 0;     // 次の期待点灯時刻（ms）
boolean ledOn        = false; // LED点灯状態
long    lastJitter   = 0;     // 直近の遅延値（画面表示用）

NoteJob[] activeNotes;           // 音を管理する配列
class NoteJob {
  InstrumentModule inst;         // 音符を担当するinstrument
  boolean        done;

  NoteJob(InstrumentModule i) {
    inst = i; done = false;
  }

  void stop() {                                //音符を止めるメソッド
    if (!done) {
      inst.noteOff(); // InstrumentModuleのnoteOff()を呼ぶ
      done = true;
    }
  }
}

void setup(){
  size(600, 400);
  myPort = new Serial(this, "", 115200);    //シリアル通信の設定(""にはArduinoのポート番号を入力)
  minim = new Minim(this);
  out = minim.getLineOut();

  // draw()の呼び出し間隔がそのまま遅延計測の分解能になるため、
  // 上限いっぱいまで回るよう高い値を要求する（実際の速度は環境依存）
  frameRate(1000);

  myPort.write(0xDD);
  println("start!");
  myPort.clear();
}

void draw() {
  checkdata();
  background(0);
  stroke(255);
  for(int i = 0; i < out.bufferSize() - 1; i++)        //波形の表示処理
  {
    line( i, 50 + out.left.get(i)*50, i+1, 50 + out.left.get(i+1)*50 );
  }

  measureDelay();   // 遅延計測とLED表示（LED_delay_measure.pde から結合）
}

// BPMに合わせてLED（円）を点灯し、今回の遅延（ズレ）だけを計測する
// （LED_delay_measure.pde の draw() 内の計測ブロックを関数化したもの）
void measureDelay() {
  if (tempo > 0) {
    long interval_ms = (long)(60000.0 / tempo);  // 1拍の長さ（ms）へ型キャスト
    long now         = millis();

    if (now >= expectedTime) {
      long ledTime = millis();
      ledOn = !ledOn;   // 論理否定演算子で点灯状態をトグルする

      if (ledOn) {
        // 期待点灯時刻と実際の点灯時刻のズレ（今回の遅延のみ）
        long jitter = ledTime - expectedTime;
        lastJitter  = jitter;
        println("[遅延] " + jitter + " ms");
      }

      // ドリフト防止のため実際の時刻ではなく期待値に加算する
      expectedTime += interval_ms;
    }
  }

  // LEDの代わりに円を描画する（三項演算子で点灯時は白、消灯時は暗灰色を選ぶ）
  noStroke();
  fill(ledOn ? 255 : 40);
  ellipse(width / 2, height / 2 + 40, 120, 120);

  // 現在のBPMと直近の遅延を画面に表示する
  // （デフォルトフォントは日本語を描画できないため表示文字列は英数字のみ）
  fill(255);
  textAlign(CENTER);
  text("BPM: " + nf(tempo, 0, 1), width / 2, height - 40);
  text("delay: " + lastJitter + " ms", width / 2, height - 20);
}

void checkdata() {                //データの処理を行う関数
  if (myPort.available() < 1) return;
  int b1 = myPort.read();
  if(b1 == 0xAA){
    if (!waitForData(1)) return;
    int b2 = myPort.read();
    if (b2 == 0x55)  {
      if(!dataLoaded) {
        readData();
      }
    }
  }else if (b1 == 0xBB) {
      if (!waitForData(1)) return;
      int b2 = myPort.read();
      if (b2 == 0x66) {
        if (!waitForData(4)) return;
        readbpm();
      }

  }else if (b1 == 0xCC) {
    // 発音ヘッダー
    if (!waitForData(1)) return;
    if (myPort.read() != 0x33) return;
    readNoteEvent();

  }

}

void readbpm() {
  if(myPort.available() >= 4){     //4バイト以上だったら処理開始
    byte[] buf = myPort.readBytes(4);

    if (buf != null && buf.length == 4) {

      ByteBuffer bb = ByteBuffer.wrap(buf);
      bb.order(ByteOrder.LITTLE_ENDIAN);
      tempo = bb.getFloat();
      println("現在のBPM:" + tempo);

      // BPM受信時刻と次の期待点灯時刻を記録する
      // （LED_delay_measure.pde の applyBpm() ＝ Arduino版のUDP受信ブロックに相当）
      if (tempo > 0) {   // ゼロ除算を避けるガード
        receiveTime = millis();  // millis()はint返しだがlongへ暗黙の拡大変換で代入される
        long interval_ms = (long)(60000.0 / tempo);
        expectedTime = receiveTime + interval_ms;
      }
      }
  }
 }
void readNoteEvent() {
  if (!waitForData(2)) { myPort.clear(); return; }

  int index  = myPort.read() & 0xFF; // 音符インデックス
  int onOff  = myPort.read() & 0xFF; // 1=ON 0=OFF

  if (activeNotes == null && N > 0) {
    activeNotes = new NoteJob[N];
    println("readNoteEvent内でactiveNotes初期化 N=" + N);
  }
  if (index < 0 || index >= N) {
    println("index範囲外: " + index + " N=" + N);
    return;
  }

  InstrumentConfig flute = new InstrumentConfig();

    flute.out = out;
    flute.waves = new String[] { "SINE", "SINE", "SINE", "SINE", "SINE" };

    // melody[index] の音階名を周波数に変換して、この音の基音にする
    flute.baseFreq = Frequency.ofPitch(melody[index]).asHz();

    flute.harmonics = new float[] { 0.9, 1.0, 0.05, 0.01, 0.002 };
    flute.cutoff = 950.0;
    flute.res = 0.0;
    flute.filterMode = 0;

    // amplitudes[index] を使って、音ごとの強弱を変える
    // （結合元の flute_communication.pde ではループ外の未定義変数 i を
    //   参照していたため index に修正）
    flute.vol = amplitudes[index];

    flute.atk = 0.02;
    flute.dec = 0.5;
    flute.sus = 0.7;
    flute.rel = 0.1;

    flute.vibratoRate  = 8.0;
    flute.vibratoDepth = 4.0;

    InstrumentModule inst = new InstrumentModule(flute);



  if (onOff == 1) {
    inst.noteOn(0); // Arduinoがタイミングを管理するため0でOK
    activeNotes[index] = new NoteJob(inst);  //クラスの配列に発音した情報を記録する
    println("NOTE_ON: " + melody[index]);

  } else if (onOff == 0) {
    // NOTE_OFF：対応するNoteJobのstop()を呼ぶ
    if (activeNotes[index] != null) {
      activeNotes[index].stop();
      activeNotes[index] = null;
      println("NOTE_OFF: " + index);
    }
  }
}
void readData() {

  if (!waitForData(1)) return;
  N = myPort.read() & 0xFF;
  if (N <= 0 || N > 100) {
    println("invalid N:", N);
    N = 0;
    return;
  }
  activeNotes = new NoteJob[N];
//string配列受信
  melody = new String[N];
  for (int i = 0; i < N; i++) {
    if (!waitForData(1)) {
      println("String長さ受信タイムアウト i=" + i);
      return;
    }
    int strLen = myPort.read() & 0xFF;

    if (!waitForData(strLen)) {
      println("String本体受信タイムアウト i=" + i);
      return;
    }
    byte[] strBuf = myPort.readBytes(strLen);
    melody[i] = new String(strBuf, java.nio.charset.StandardCharsets.UTF_8);
  }
  println("melody");
  printArray(melody);

  //各配列受信
  int totalBytes = N * 4 * 1;     //要素数 * バイト数 * 配列数

  if (!waitForData(totalBytes)) {
    println("配列データの受信タイムアウト");
    println("  → Processingが待っていたバイト数: " + totalBytes + " バイト");
    println("  → 実際にシリアルポートに届いたバイト数: " + myPort.available() + " バイト");
    println("--------------------------------------------------");
    return;
  }

  byte[] buf = myPort.readBytes(totalBytes);
  ByteBuffer bb = ByteBuffer.wrap(buf);
  bb.order(ByteOrder.LITTLE_ENDIAN);

  amplitudes = new float[N];
  // 4番目：amplitudes
  for (int i = 0; i < N; i++) {
    amplitudes[i] = bb.getFloat();
  }



  println("amplitudes");
  printArray(amplitudes);

  println("受信成功");
  if (activeNotes != null) {
    for (int i = 0; i < activeNotes.length; i++) {
      if (activeNotes[i] != null) {
        activeNotes[i].stop();
        activeNotes[i] = null;
      }
    }
  }
  dataLoaded = true;
  activeNotes = new NoteJob[N];
  myPort.write(0xFF);
  println("READY送信");
  myPort.clear();
}

boolean waitForData(int requiredBytes) {
  int waitStart = millis();
  while (myPort.available() < requiredBytes) {
    if (millis() - waitStart > 20) {
      return false;
    }
    delay(1);
  }
  return true;
}
