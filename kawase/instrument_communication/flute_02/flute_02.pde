// flute_02.pde
// Arduino からシリアルで BPM・ノート情報（1音ずつ）を受信して演奏しつつ、
// FFTスペクトラム・歌詞・鍵盤・遅延計測を表示するスケッチ。
//
// 構成:
//   - シリアル受信   : 0xAA 0x55=ノート情報（index+音名+音量）、0xBB 0x66=BPM、0xCC 0x33=消音
//   - 遅延計測       : LED_delay_measure.pde 由来。BPM から期待点灯時刻を計算し、
//                      実際の点灯処理時刻とのズレ（ms）を右上に表示する
//   - InstrumentConfig / InstrumentModule クラスは同フォルダの InstrumentModule.pde に定義

import ddf.minim.*;
import ddf.minim.ugens.*;
import ddf.minim.analysis.*; // FFT解析用
import processing.serial.*;
import java.nio.*;

Serial myPort;
float tempo = 0.0;
float updatedtempo = 0.0;
AudioOutput out;
Minim minim;
InstrumentModule flute;

// ===== FFT =====
FFT fft;

final int numBands = 16;
float[] bandValues = new float[numBands];

float minDB = 0;
float maxDB = 80;

int fftX;
int fftY;
int fftW;
int fftH;

float waveCenter;
float waveAmp;
// ===============

// ===== 歌詞 =====
PFont font;

String[] lyrics = {
  "きらきらひかるおそらのほしよ",
  "まばたきしてはみんなをみてる",
  "きらきらひかるおそらのほしよ"
};

int[] lyricStart = {0, 14, 28};
int[] lyricEnd   = {14, 28, 42};

int currentLyric = 0;
float lyricProgress = 0;
// ==========

//---鍵盤
String[] pianoKeys = {
  "C4","D4","E4","F4",
  "G4","A4","B4","C5"
};
String[] pianoLabels = {
  "ド","レ","ミ","ファ",
  "ソ","ラ","シ","ド"
};

boolean[] keyOn = new boolean[pianoKeys.length];
//----

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
  String noteName;               // 鍵盤表示のために音名を保持する

  NoteJob(InstrumentModule i, String n) {
    inst = i;
    noteName = n;
    done = false;
  }

  void stop() {                                //音符を止めるメソッド
    if (!done) {
      inst.noteOff(); // InstrumentModuleのnoteOff()を呼ぶ
      done = true;
    }
  }
}

void setup(){
  size(1100, 1000);
  updateLayout();
  font = createFont("YuMin-Medium", 42, true);
  textFont(font);
  // シリアル通信の設定（Arduinoのポートパスは環境に合わせて変更する）
  myPort = new Serial(this, "/dev/tty.usbmodem48CA4359FD002", 115200);
  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO,1024);
  fft = new FFT(out.bufferSize(), out.sampleRate());
  activeNotes = new NoteJob[100];
  myPort.write(0xDD);
  println("start!");
  myPort.clear();
}

//---
void windowResized() {
    updateLayout();
}
//---

//---
void updateLayout() {

  // FFT
  fftX = int(width * 0.03);
  fftY = int(height * 0.70);
  fftW = int(width * 0.94);
  fftH = int(height * 0.25);

  // 波形
  waveCenter = height * 0.50;
  waveAmp = height * 0.12;
}
//---


void draw() {
  checkdata();
  background(0);
  stroke(255);
  for (int x = 0; x < width - 1; x++) {

  int i1 = int(map(x, 0, width - 1, 0, out.bufferSize() - 1));
  int i2 = int(map(x + 1, 0, width - 1, 0, out.bufferSize() - 1));

  line(
    x,
    waveCenter + out.left.get(i1) * waveAmp,
    x + 1,
    waveCenter + out.left.get(i2) * waveAmp
  );
  }
  //---
  fft.forward(out.mix);

  updateSpectrum();

  drawSpectrum();

  updateLyrics();
  drawLyrics();

  updateKeyboard();
  drawKeyboard();

  measureDelay();   // 遅延計測とLED表示（LED_delay_measure.pde から結合）
  //---
}

// BPMに合わせてLED（円）を点灯し、今回の遅延（ズレ）だけを計測する
// （LED_delay_measure.pde の計測ブロック。表示は画面右上）
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

  // LEDの代わりに円を右上へ描画する（三項演算子で点灯時は白、消灯時は暗灰色を選ぶ）
  noStroke();
  fill(ledOn ? 255 : 40);
  float d = height * 0.05;
  ellipse(width * 0.93, height * 0.06, d, d);

  // 直近の遅延値をLED円の下に表示する
  fill(255);
  textAlign(CENTER, TOP);
  textSize(height * 0.018);
  text("delay: " + lastJitter + " ms", width * 0.93, height * 0.06 + d * 0.7);
}

//----
void updateSpectrum() {

  for (int i = 0; i < numBands; i++) {

    int index =
      int(map(i,0,numBands,0,fft.specSize()));

    float value = fft.getBand(index);

    bandValues[i] = 20 * log(value + 1);

    bandValues[i] =
      constrain(bandValues[i],minDB,maxDB);
  }
}
//----

//----
void drawSpectrum() {

  float barWidth = fftW/(float)numBands;

  noStroke();

  for(int i=0;i<numBands;i++){

    float x=fftX+i*barWidth;

    float h=
      map(bandValues[i],
          minDB,maxDB,
          0,fftH);

    fill(
      map(i,0,numBands-1,50,255),
      map(h,0,fftH,80,220),
      map(i,0,numBands-1,255,80)
    );

    rect(
      x+3,
      fftY+fftH-h,
      barWidth-6,
      h
    );
  }

  stroke(120);
  noFill();
  rect(fftX,fftY,fftW,fftH);

  drawAxis();
}
//----

//----
void drawAxis() {

  stroke(180);
  fill(255);
  textSize(height * 0.015);

  // ===== 縦軸(dB) =====
  int divY = 4;

  for (int i = 0; i <= divY; i++) {

    float y = map(i, 0, divY, fftY + fftH, fftY);

    line(fftX - 5, y, fftX, y);

    float value = map(i, 0, divY, minDB, maxDB);

    textAlign(RIGHT, CENTER);
    text(int(value), fftX - 10, y);
  }

  // 縦軸タイトル
  pushMatrix();
  translate(fftX - 50, fftY + fftH/2);
  rotate(-HALF_PI);
  textAlign(CENTER, CENTER);
  text("Level", 0, 0);
  popMatrix();


  // ===== 横軸(Hz) =====
  textAlign(CENTER, TOP);

  for (int i = 0; i < numBands; i++) {

    float x = fftX + (i + 0.5) * fftW / numBands;

    int bandIndex = int(map(i, 0, numBands, 0, fft.specSize()));
    int freq = int(fft.indexToFreq(bandIndex));

    line(x, fftY + fftH, x, fftY + fftH + 5);

    if (freq >= 1000)
      text(nf(freq / 1000.0, 0, 1) + "k", x, fftY + fftH + 8);
    else
      text(freq, x, fftY + fftH + 8);
  }

  // 横軸タイトル
  textAlign(CENTER);
  text("Frequency (Hz)", fftX + fftW/2, fftY + fftH + 35);
}
//----

void checkdata() {                //データの処理を行う関数
  if (myPort.available() < 1) return;
  int b1 = myPort.read();
  if(b1 == 0xAA){
    if (!waitForData(1)) return;
    int b2 = myPort.read();
    if (b2 == 0x55)  {
      if(!dataLoaded) {
        readNote();
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
    readNoteOff();

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
      // （LED_delay_measure.pde の遅延計測の起点。Arduino版のUDP受信ブロックに相当）
      if (tempo > 0) {   // ゼロ除算を避けるガード
        receiveTime = millis();  // millis()はint返しだがlongへ暗黙の拡大変換で代入される
        long interval_ms = (long)(60000.0 / tempo);
        expectedTime = receiveTime + interval_ms;
      }
      }
  }
 }

void readNote() {
  if (!waitForData(1)) return;
  int index = myPort.read() & 0xFF; //  インデックスを受信
  if (!waitForData(1)) return;
  int namelen = myPort.read() & 0xFF;
  println(namelen);

  if (!waitForData(namelen)) return;
  byte[] nameBuf = myPort.readBytes(namelen);
  String noteName = new String(nameBuf, java.nio.charset.StandardCharsets.UTF_8);
  println("NOTE:" + noteName);
  if (!waitForData(4)) return;
  byte[] ampBuf = myPort.readBytes(4);
  ByteBuffer bb = ByteBuffer.wrap(ampBuf);
  bb.order(ByteOrder.LITTLE_ENDIAN);
  float amp = bb.getFloat();
  println("amplitude" + amp);

  InstrumentConfig flute = new InstrumentConfig();

    flute.out = out;
    flute.waves = new String[] { "SINE", "SINE", "SINE", "SINE", "SINE" };

    // 受信した音階名を周波数に変換して、この音の基音にする
    flute.baseFreq = Frequency.ofPitch(noteName).asHz();

    flute.harmonics = new float[] { 0.9, 1.0, 0.05, 0.01, 0.002 };
    flute.cutoff = 950.0;
    flute.res = 0.0;
    flute.filterMode = 0;

    // 受信した amp を使って、音ごとの強弱を変える
    flute.vol = amp;

    flute.atk = 0.02;
    flute.dec = 0.5;
    flute.sus = 0.7;
    flute.rel = 0.1;

    flute.vibratoRate  = 8.0;
    flute.vibratoDepth = 4.0;

    InstrumentModule inst = new InstrumentModule(flute);


    // 例外処理（try-catch）で発音時のエラーを捕捉してスケッチ停止を防ぐ
    try {
    //  NOTE_ON：meloinstrumentを生成してnoteOn()を直接呼ぶ
    inst.noteOn(0); // Arduinoがタイミングを管理するためdurは0でOK
    activeNotes[index] = new NoteJob(inst, noteName);
    println("NOTE_ON: " + index);
    } catch (Exception e) { println("発音エラー: " + e.getMessage()); }
}

void readNoteOff() {
    if (!waitForData(1)) return;
    int index = myPort.read() & 0xFF;
    println("NOTE_OFF " + index );
    // NOTE_OFF：対応するNoteJobのstop()を呼ぶ
    if (activeNotes[index] != null) {
      activeNotes[index].stop();
      activeNotes[index] = null;
    }
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

void updateLyrics() {

  int note = -1;

  for (int i = 0; i < activeNotes.length; i++) {
    if (activeNotes[i] != null) {
      note = i;
    }
  }

  if (note < 0) return;

  for (int i = 0; i < lyrics.length; i++) {

    if (note >= lyricStart[i] &&
        note < lyricEnd[i]) {

      currentLyric = i;

      lyricProgress =
      (note - lyricStart[i] + 1) /
      float(lyricEnd[i] - lyricStart[i]);

      break;
    }
  }
}

void drawLyrics() {

  textSize(height*0.05);
  textAlign(CENTER,CENTER);

  float y = height*0.12;

  String lyric = lyrics[currentLyric];

  float tw = textWidth(lyric);

  float left = width/2 - tw/2;

  fill(255);
  text(lyric,width/2,y);

  push();

  // clip()で描画領域を切り取り、歌詞の進行部分だけを黄色で重ね描きする
  clip(
    int(left),
    int(y-35),
    int(tw*lyricProgress),
    70
  );

  fill(255,220,0);

  text(lyric,width/2,y);

  noClip();

  pop();
}

void updateKeyboard() {

  for (int i = 0; i < keyOn.length; i++) {
    keyOn[i] = false;
  }

  for (int i = 0; i < activeNotes.length; i++) {

    if (activeNotes[i] != null) {

      String n = activeNotes[i].noteName;

      for (int k = 0; k < pianoKeys.length; k++) {

        if (n.equals(pianoKeys[k])) {
          keyOn[k] = true;
        }
      }
    }
  }
}

void drawKeyboard() {

  float totalWidth = width * 0.70;
  float keyWidth = totalWidth / pianoKeys.length;

  float left = width/2 - totalWidth/2;

  float y = height * 0.24;
  float h = height * 0.10;

  stroke(0);

  textAlign(CENTER, CENTER);
  textSize(height * 0.022);

  for (int i = 0; i < pianoKeys.length; i++) {

    float yy = y;

    if (keyOn[i]) {
      fill(255, 220, 0);   // 光る
      yy += 4;             // 少し沈む
    } else {
      fill(255);
    }

    rect(left + i * keyWidth,
         yy,
         keyWidth,
         h);

    fill(0);

    text(
      pianoLabels[i],
      left + i * keyWidth + keyWidth/2,
      yy + h/2
    );
  }
}


void keyPressed() {
  // ENTERキーで演奏をリスタートする（FFT・発音管理・遅延計測を初期化して開始信号を再送）
  if (key == ENTER || key == RETURN){
     fft = new FFT(out.bufferSize(), out.sampleRate());
     activeNotes = new NoteJob[100];

     // 遅延計測もリセットする（次のBPM受信で再初期化される）
     tempo        = 0;
     receiveTime  = 0;
     expectedTime = 0;
     ledOn        = false;
     lastJitter   = 0;

     myPort.write(0xDD);
     println("start!");
     myPort.clear();
  }
}
