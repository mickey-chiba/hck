import ddf.minim.*;
import ddf.minim.ugens.*;
import processing.serial.*;
import java.nio.*;
//----
import ddf.minim.analysis.*;
//----



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

// ===== LED遅延検出(Arduino側 LED_delay_measure.ino の移植) =====
int     prevMillis     = 0;     // 実LEDの前回点滅切り替え時刻
boolean ledOn          = false; // 実LEDのON/OFF状態
int     refPrevMillis  = 0;     // 基準LEDの前回点滅時刻(理想タイミング用)
boolean refLedOn       = false; // 基準LEDのON/OFF状態
int     expectedNextMs = 0;     // 実LEDの次の期待点灯時刻(ジッタ計算用)
float   ledBPM         = -1;    // LEDタイミング計算に使用中のBPM(変化検出用)

// ジッタのCSV記録用
PrintWriter jitterLog;               // CSVファイルへの書き込みストリーム
FloatList   jitterValues;            // サマリー計算用にジッタ値を貯めるリスト(Processing組み込みの可変長float配列)
String      jitterLogName;           // 保存したCSVのファイル名(終了時の案内表示用)
// ==============================================================

// musicalTime管理 
boolean   playing     = false;
float     musicalTime = 0;
long      lastTimeMs  = 0;
boolean[] noteStarted;

NoteJob[] activeNotes;           // 音を管理する配列
class NoteJob {
  InstrumentModule inst;         // 音符を担当するinstrument
  boolean        done;   
  String noteName;

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
  // シリアル通信の設定(""にはArduinoのポート番号を入力)
  // Arduino未接続でもジッタ計測のテストができるよう、失敗しても止まらずに続行する
  try {
    myPort = new Serial(this, "dev/tty.usbmodem48CA4359FD002", 115200);
  } catch (Exception e) {  // 例外処理: ポートが開けない場合はnullのまま進む
    myPort = null;
    println("NO SERIAL PORT (test mode: press T to set BPM 120)");
  }
  minim = new Minim(this);
  //out = minim.getLineOut();
  //-----
  out = minim.getLineOut(Minim.STEREO,1024);
  fft = new FFT(out.bufferSize(), out.sampleRate());
  //-----
  activeNotes = new NoteJob[100];

  // ジッタ記録の準備: 実行日時入りのファイル名でCSVを開き、ヘッダー行を書く
  jitterLogName = String.format("jitter_log_%04d%02d%02d_%02d%02d%02d.csv",
    year(), month(), day(), hour(), minute(), second());
  jitterLog = createWriter(jitterLogName);   // スケッチフォルダ内に作成される
  jitterLog.println("actual_ms,expected_ms,jitter_ms,bpm");  // CSVヘッダー
  jitterValues = new FloatList();

  if (myPort != null) {
    myPort.write(0xDD);
    println("start!");
    myPort.clear();
  }
}

// スケッチ終了時(ESCキーやウィンドウを閉じたとき)に呼ばれる関数をオーバーライドして、
// サマリー表示とCSVのクローズを確実に行う
void exit() {
  printJitterSummary();
  if (jitterLog != null) {
    jitterLog.flush();
    jitterLog.close();
    println("CSV saved: " + jitterLogName);
  }
  super.exit();  // 本来の終了処理を呼ぶ(これを忘れるとウィンドウが閉じない)
}

// 記録したジッタの統計サマリーをコンソールに表示する
void printJitterSummary() {
  int n = (jitterValues == null) ? 0 : jitterValues.size();
  if (n == 0) {
    println("NO JITTER DATA (no BPM received)");
    return;
  }

  // 平均を計算
  float mean = jitterValues.sum() / n;

  // 標準偏差(ジッタのバラつき)を計算
  float sqSum = 0;
  for (int i = 0; i < n; i++) {
    float d = jitterValues.get(i) - mean;
    sqSum += d * d;
  }
  float std = sqrt(sqSum / n);

  // 絶対値でソートしたコピーを作り、最大値と95パーセンタイルを求める
  FloatList absSorted = new FloatList();
  for (int i = 0; i < n; i++) {
    absSorted.append(abs(jitterValues.get(i)));
  }
  absSorted.sort();
  float maxAbs = absSorted.get(n - 1);
  int p95Index = min(n - 1, ceil(n * 0.95) - 1);  // 95%の値が収まる位置
  float p95 = absSorted.get(p95Index);

  println("===== JITTER SUMMARY =====");
  println("samples : " + n + " beats");
  println("mean    : " + nf(mean, 0, 1) + " ms");
  println("stddev  : " + nf(std, 0, 1) + " ms");
  println("max(abs): " + nf(maxAbs, 0, 1) + " ms");
  println("p95(abs): " + nf(p95, 0, 1) + " ms");
  println("==========================");
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

  // BPM同期LEDの点滅更新とジッタ計測・仮想LED描画
  updateLedDelay();
  drawLedIndicators();
  //---
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
  if (myPort == null) return;           // シリアル未接続(テストモード)なら何もしない
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
      }
  }
 }

// BPM同期LEDの点滅とジッタ計測(Arduino側 loop() 末尾の処理と同じロジック)
void updateLedDelay() {
  if (tempo <= 0) return;  // BPM未受信の間は動作しない

  // BPMから1拍あたりの間隔(ms)を計算: 60000ms ÷ BPM
  int interval = int(60000.0 / tempo);
  int now = millis();

  // BPM変化(または初回)で両LEDのタイミング基準をリセットする
  if (tempo != ledBPM) {
    prevMillis = now;
    refPrevMillis = now;
    expectedNextMs = 0;  // ジッタ計算も初回扱いにリセット
    ledBPM = tempo;
  }

  // 実LED: 実際の点灯時刻(now)で基準を更新する(Arduinoのピン3側と同じ)
  if (now - prevMillis >= interval) {
    // 2拍目以降: 期待点灯時刻との差(ジッタ)をコンソール出力し、CSVにも記録する
    if (expectedNextMs > 0) {
      int jitter = now - expectedNextMs;  // 正なら遅れ、負なら早い
      // Windowsのコンソールで日本語が文字化けするため、計測系の出力は英数字のみにする
      println("[jitter] " + jitter + " ms");
      jitterLog.println(now + "," + expectedNextMs + "," + jitter + "," + nf(tempo, 0, 1));
      jitterLog.flush();  // 途中で強制終了してもデータが残るよう毎回書き出す
      jitterValues.append(jitter);
    }
    prevMillis = now;                    // 実際の点灯時刻で更新
    expectedNextMs = now + interval;     // 次の期待点灯時刻 = 今回の実点灯 + 1拍
                                         // (更新前のprevMillisを使うと1拍ズレた値になる)
    ledOn = !ledOn;
  }

  // 基準LED: 期待時刻から次を計算するためドリフトしない(LED_BUILTIN側と同じ)
  if (now - refPrevMillis >= interval) {
    refPrevMillis += interval;
    refLedOn = !refLedOn;
  }
}

// 実LEDと基準LEDを画面右上に描画する(物理LEDの代わりの仮想LED)
void drawLedIndicators() {
  float r = height * 0.018;       // LEDの半径
  float x = width  * 0.90;
  float y = height * 0.04;

  noStroke();
  textSize(height * 0.015);
  textAlign(CENTER, TOP);

  // 実LED(ジッタ計測対象)
  fill(ledOn ? color(255, 60, 60) : color(70, 20, 20));
  ellipse(x, y, r * 2, r * 2);
  fill(255);
  text("実LED", x, y + r + 4);

  // 基準LED(理想タイミング)
  float x2 = x + r * 4;
  fill(refLedOn ? color(60, 255, 60) : color(20, 70, 20));
  ellipse(x2, y, r * 2, r * 2);
  fill(255);
  text("基準", x2, y + r + 4);
}

void readNote() {
//  while (myPort.available() > 0) {
//    int b = myPort.read() & 0xFF;
//    print(String.format("%02X ", b));
//}
//println();
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
  //println(
  //  hex(ampBuf[0] & 0xFF) + " " +
  //  hex(ampBuf[1] & 0xFF) + " " +
  //  hex(ampBuf[2] & 0xFF) + " " +
  //  hex(ampBuf[3] & 0xFF)
  //);
  ByteBuffer bb = ByteBuffer.wrap(ampBuf);
  bb.order(ByteOrder.LITTLE_ENDIAN);
  float amp = bb.getFloat();
  println("amplitude" + amp);
    
  InstrumentConfig flute = new InstrumentConfig();

    flute.out = out;
    flute.waves = new String[] { "SINE", "SINE", "SINE", "SINE", "SINE" };

    // 受信した音階名(noteName)を周波数に変換して、この音の基音にする
    flute.baseFreq = Frequency.ofPitch(noteName).asHz();

    flute.harmonics = new float[] { 0.9, 1.0, 0.05, 0.01, 0.002 };
    flute.cutoff = 950.0;
    flute.res = 0.0;
    flute.filterMode = 0;

    // 受信した振幅(amp)を使って、音ごとの強弱を変える
    flute.vol = amp;

    flute.atk = 0.02;
    flute.dec = 0.5;
    flute.sus = 0.7;
    flute.rel = 0.1;

    flute.vibratoRate  = 8.0;
    flute.vibratoDepth = 4.0;

    InstrumentModule inst = new InstrumentModule(flute);


    try {
    //  NOTE_ON：meloinstrumentを生成してnoteOn()を直接呼ぶ
    inst.noteOn(0); // Arduinoがタイミングを管理するためdurは0でOK
    activeNotes[index] = new NoteJob(inst, noteName);
    //n++;
    println("NOTE_ON: " + index);
    } catch (Exception e) { println("発音エラー: " + e.getMessage()); }
}
void readNoteOff() {
    if (!waitForData(1)) return;
    int index = myPort.read() & 0xFF;
    println("NOTE_OFF " + index );
    // ★ NOTE_OFF：対応するNoteJobのstop()を呼ぶ
    if (activeNotes[index] != null) {
      activeNotes[index].stop();
      activeNotes[index] = null;
      //println("NOTE_OFF: " + index);
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


 //音色設定用のパラメータオブジェクト
class InstrumentConfig {
  AudioOutput out;

  String[] waves;
  float baseFreq;
  float[] harmonics;

  float cutoff;
  float res;
  int filterMode;

  float fcoRate;
  float fcoAmount;

  float vol;
  float atk;
  float dec;
  float sus;
  float rel;
  float vibratoRate  = 0.0; // 揺れる速さ (Hz) 0で無効
  float vibratoDepth = 0.0; // 揺れ幅 (Hz)

}

// 楽器モジュール（クラス）の設計図
// Minim の Instrument として使えるように implements Instrument を付ける
class InstrumentModule implements Instrument {
  AudioOutput _out;
  // 複数の波形をまとめて1つの音にするためのミキサー
  Summer _summer;
  // 実際に音を鳴らす波形オシレーターの配列
  Oscil[] _waves;
  // フィルターのカットオフ周波数を揺らすためのオシレーター
  Oscil _fco;
  // 音色を変化させるフィルター
  MoogFilter _filter;
  // 音の立ち上がり、減衰、持続、余韻を制御するADSR
  ADSR _adsr;
  Oscil _vibrato; // ← 追加

  // 波形を複数組み合わせる版のコンストラクタ
  InstrumentModule(InstrumentConfig config) {
    _out = config.out;

    String[] waves = config.waves;
    float baseFreq = config.baseFreq;
    float[] harmonics = config.harmonics;

    // 波形が指定されていない場合は、初期値としてSINE波を使う
    if (waves == null || waves.length == 0) {
      waves = new String[] { "SINE" };
    }

    // 倍音が指定されていない場合は、基音だけを鳴らす
    if (harmonics == null || harmonics.length == 0) {
      harmonics = new float[] { 1.0 };
    }

    // 複数のOscilをまとめるためのSummerを作る
    _summer = new Summer();

    // 必要なOscilの数を計算する
    // 波形の数 × 倍音の数
    int waveTotal = waves.length * harmonics.length;
    _waves = new Oscil[waveTotal];

    // _waves配列の何番目に入れるかを管理する番号
    int index = 0;

    // 指定された波形の数だけ繰り返す
    for (int w = 0; w < waves.length; w++) {

      // 文字列で指定された波形名を、Minimで使えるWaveformに変換する
      Waveform waveform = getWaveform(waves[w]);

      // 指定された倍音の数だけ繰り返す
      for (int i = 0; i < harmonics.length; i++) {

        // 基音の周波数に、1倍、2倍、3倍...をかけて倍音の周波数を作る
        float freq = baseFreq * (i + 1);

        // 倍音ごとの音量を決める
        // 複数波形を足すと音量が大きくなりすぎるので、波形数で割る
        float amp = config.vol  * harmonics[i] / waves.length;

        // Oscilを作る
        _waves[index] = new Oscil(freq, amp, waveform);

        // 作ったOscilをSummerに接続する
        _waves[index].patch(_summer);

        // 次のOscilを配列に入れるため、番号を進める
        index++;
      }
    }

    // フィルターを作る
    // filterMode によって LP, HP, BP を切り替える
    _filter = new MoogFilter(
      config.cutoff,
      config.res,
      getFilterType(config.filterMode)
    );

    // FCOを使う場合
    // fcoRate は揺れる速さ、fcoAmount は揺れ幅
    if (config.fcoRate > 0 && config.fcoAmount > 0) {

      // フィルターのカットオフ周波数を揺らすためのOscilを作る
      _fco = new Oscil(config.fcoRate, config.fcoAmount, Waves.SINE);

      // 揺れの中心を cutoff の値にする
      _fco.offset.setLastValue(config.cutoff);

      // FCOをフィルターのfrequencyに接続する
      _fco.patch(_filter.frequency);
    }
    if (config.vibratoRate > 0 && config.vibratoDepth > 0)
    {
      _vibrato = new Oscil(config.vibratoRate, config.vibratoDepth, Waves.SINE);
      for (int i = 0; i < _waves.length; i++)
      {
        float freq = _waves[i].frequency.getLastValue();
        // 倍音ごとに揺れ幅を周波数比で調整する
        float scaledDepth = config.vibratoDepth * (freq / config.baseFreq); // ← 追加
        _vibrato = new Oscil(config.vibratoRate, scaledDepth, Waves.SINE);  // ← 各音に個別に作る
        _vibrato.offset.setLastValue(freq);
        _vibrato.patch(_waves[i].frequency);
      }
    }


    // ADSRを作る
    _adsr = new ADSR(
      config.vol,
      config.atk,
      config.dec,
      config.sus,
      config.rel
    );

    // 音の流れを接続する
    // Oscilたち → Summer → Filter → ADSR → _out
    _summer.patch(_filter).patch(_adsr).patch(_out);
  }

  // 文字列で指定された波形名をMinimのWaveformに変換する関数
  Waveform getWaveform(String wave) {

    // waveがnullならSINE波を返す
    if (wave == null) {
      return Waves.SINE;
    }

    // 小文字で指定されても判定できるように大文字に変換する
    wave = wave.toUpperCase();

    if (wave.equals("SINE")) {
      return Waves.SINE;
    } else if (wave.equals("SAW")) {
      return Waves.SAW;
    } else if (wave.equals("SQUARE")) {
      return Waves.SQUARE;
    } else if (wave.equals("TRIANGLE")) {
      return Waves.TRIANGLE;
    }

    // 指定が間違っていた場合はSINE波にする
    return Waves.SINE;
  }

  // 数字で指定されたフィルター種類をMoogFilter.Typeに変換する関数
  MoogFilter.Type getFilterType(int filterMode) {

    // 0：ローパスフィルター
    if (filterMode == 0) {
      return MoogFilter.Type.LP;

    // 1：ハイパスフィルター
    } else if (filterMode == 1) {
      return MoogFilter.Type.HP;

    // 2：バンドパスフィルター
    } else if (filterMode == 2) {
      return MoogFilter.Type.BP;
    }

    // 指定が間違っていた場合はローパスにする
    return MoogFilter.Type.LP;
  }

  // 音が鳴り始めるときに呼ばれる
  void noteOn(float duration) {
    _adsr.noteOn();
  }

  // 音が終わるときに呼ばれる
  void noteOff() {

    // ADSRのReleaseを開始する
    _adsr.noteOff();

    // Releaseが終わったあと、_outから切り離す
    _adsr.unpatchAfterRelease(_out);
  }
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
  if (key == ENTER || key == RETURN){
      fft = new FFT(out.bufferSize(), out.sampleRate());
     activeNotes = new NoteJob[100];
     ledBPM = -1;  // 再スタート時はLED遅延計測もリセット(次フレームで基準を取り直す)
     if (myPort != null) {
       myPort.write(0xDD);
       println("start!");
       myPort.clear();
     }
     draw();
  }
  // テストモード: TキーでBPM 120を直接セットする(WiFi・Arduinoなしでジッタ計測できる)
  if (key == 't' || key == 'T') {
    tempo = 120.0;
    println("TEST MODE: BPM " + tempo + " set (jitter logging started)");
  }
}
