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
long[] noteOnReceived = new long[100];
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
  "C5","D5","E5","F5",
  "G5","A5","B5","C6"
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
  //size(1100, 800);
  fullScreen();
  updateLayout();
  font = createFont("YuMin-Medium", 42, true);
  textFont(font);
  myPort = new Serial(this, "/dev/tty.usbmodem34B7DA6365942", 115200);    //シリアル通信の設定(""にはArduinoのポート番号を入力)
  minim = new Minim(this);
  //out = minim.getLineOut();
  //-----
  out = minim.getLineOut(Minim.STEREO,1024);
  fft = new FFT(out.bufferSize(), out.sampleRate());
  //-----
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
  drawBPM();
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
  //println(namelen);
  
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
  //println("amplitude" + amp);
    
   InstrumentConfig flute = new InstrumentConfig();

    flute.out = out;
    flute.waves = new String[] { "SINE", "SINE", "SINE", "SINE", "SINE" };

    // melody[i] の音階名を周波数に変換して、この音の基音にする
    flute.baseFreq = Frequency.ofPitch(melody[i]).asHz();
    // flute.baseFreq = Frequency.ofPitch(pitch).asHz();

    flute.harmonics = new float[] { 0.9, 1.0, 0.05, 0.01, 0.002 };
    flute.cutoff = 950.0;
    flute.res = 0.0;
    flute.filterMode = 0;

    // amplitudes[i] を使って、音ごとの強弱を変える
    flute.vol = amplitudes[i];

    //flute.noiseVol = amplitudes[i] * 0.05;

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
    long now = millis();
    noteOnReceived[index] = now;
    println(" melody" + noteName + " NOTE_ON" + index + " t=" + now);
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
void drawBPM() {

  fill(255);

  textAlign(CENTER, CENTER);
  textSize(height * 0.035);

  text(
    "BPM : " + int(tempo),
    width / 2,
    height * 0.06
  );
}

void keyPressed() {
  if (key == ENTER || key == RETURN){
      fft = new FFT(out.bufferSize(), out.sampleRate());
     activeNotes = new NoteJob[100];
     myPort.write(0xDD);
     println("start!");
     myPort.clear();
  }
}
