import ddf.minim.*;
import ddf.minim.ugens.*;
import ddf.minim.analysis.*;
import processing.serial.*;

AudioOutput out;
Minim minim;
InstrumentModule trumpet;

// ===== FFTスペクトラム用 =====
FFT fft;
final int FFT_SIZE = 128;
int numBands = 16;
float[] bandValues = new float[numBands];

int graphX = 60, graphY = 650, graphWidth = 1680, graphHeight = 250;
float minDB = 0;
float maxDB = 80;

// ===== 日本語フォント =====
PFont font;

// ===== 歌詞表示用 =====
String[] lyrics = {"きらきら ひかる", "おそらの ほしよ", "まばたき しては", "みんなを みてる"};
int currentLyricIndex = 0;
float songStartTime = -1;
float songTotalDuration;
boolean songPlaying = false;
float lyricProgress = 0;

// ===== 星アニメーション =====
final int STAR_NUM = 50;
float[] starX = new float[STAR_NUM];
float[] starY = new float[STAR_NUM];
float[] starSpeed = new float[STAR_NUM];
float[] starSize = new float[STAR_NUM];

String melody[] = {"C5", "C5", "G5", "G5", "A5", "A5", "G5",
                   "F5", "F5", "E5", "E5", "D5", "D5", "C5",
                   "G5", "G5", "F5", "F5", "E5", "E5", "D5",
                   "G5", "G5", "F5", "F5", "E5", "E5", "D5"};
//音を鳴らす長さの配列
float duration[] = {1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f, 
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f, 
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f, 
                    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 2.0f};
//音を鳴らす開始時間の配列
float startTime[] = {0.0f, 1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f, 
                    8.0f, 9.0f, 10.0f, 11.0f, 12.0f, 13.0f, 14.0f, 
                    16.0f, 17.0f, 18.0f, 19.0f, 20.0f, 21.0f, 22.0f,
                    24.0f, 25.0f, 26.0f, 27.0f, 28.0f, 29.0f, 30.0f};
//音の大きさの配列
float amplitudes[] = {0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.6f,
                      0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.7f, 
                      0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.8f,
                      0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.9f};


void setup(){
  size(1800, 1000);
  frameRate(60);

  // 日本語フォント設定
  font = createFont("YuMin-Medium", 40, true);
  textFont(font);

  // 星の初期化
  for (int i = 0; i < STAR_NUM; i++) {
    starX[i] = random(20, width - 20);
    starY[i] = random(380, 460);
    starSpeed[i] = random(0.3, 1.0);
    starSize[i] = random(2, 6);
  }

  minim = new Minim(this);
  out = minim.getLineOut();
  out.setTempo( 80 );
  pixelDensity(1);

  // FFT初期化
  fft = new FFT(out.bufferSize(), out.sampleRate());

  // 曲の総再生時間を計算
  songTotalDuration = startTime[startTime.length - 1] + duration[duration.length - 1];
}
void draw(){
  background(20);

  // FFT解析
  fft.forward(out.left);

  // スペクトラムデータ更新
  updateSpectrum();

  // 波形描画（改良版）
  drawWaveform();

  // 歌詞インデックス更新
  updateLyricIndex();

  // 歌詞表示
  drawLyrics();

  // FFTスペクトラム描画
  drawVerticalAxis();
  drawSpectrum();
  drawFrequencyLabels();

  // タイトル
  fill(255);
  textSize(14);
  textAlign(LEFT, BASELINE);
  text("Waveform (Time Domain)", 20, 35);
  text("FFT Spectrum", 20, graphY - 20);

  fill(255,255,180);
  textSize(30);
  textAlign(CENTER);
  text("♫ きらきら星 (トランペット)", width/2, 80);

  // FPS表示
  fill(255);
  textSize(20);
  textAlign(RIGHT);
  text("FPS: " + nf(frameRate, 0, 1), width - 30, 40);
  textAlign(LEFT, BASELINE);
}







// 音色設定用のパラメータオブジェクト
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
class Instrumentmodule implements Instrument {
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
  Instrumentmodule(InstrumentConfig config) {
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
void playSong() {
  out.pauseNotes();

  // 歌詞再生開始
  songStartTime = millis();
  songPlaying = true;
  currentLyricIndex = 0;

  // meloinstrumentのインスタンスを音符ごとに生成
   for (int i = 0; i < melody.length; i++) {
    InstrumentConfig trumpet = new InstrumentConfig();
    trumpet.out = out;
    trumpet.waves = new String[] { "SAW", "SQUARE"};

    // melody[i] の音階名を周波数に変換して、この音の基音にする
    trumpet.baseFreq = Frequency.ofPitch(melody[i]).asHz();

    trumpet.harmonics = new float[] { 1.0, 0.7, 0.8, 0.6, 0.4, 0.35, -0.3, -0.2, -0.1, -0.05 };
    trumpet.cutoff = 1500.0;
    trumpet.res = 0.1;
    trumpet.filterMode = 0;
    trumpet.fcoRate = 0.0;
    trumpet.fcoAmount = 1000.0;

    // amplitudes[i] を使って、音ごとの強弱を変える
    trumpet.vol = amplitudes[i];

    trumpet.atk = 0.002;
    trumpet.dec = 0.03;
    trumpet.sus = 0.7;
    trumpet.rel = 0.3;
    trumpet.vibratoRate  = 8.0;
    trumpet.vibratoDepth = 4.0;

    out.playNote(startTime[i], duration[i], new Instrumentmodule(trumpet));
   }

  out.resumeNotes();
}
void keyPressed() {
  switch (key) {
    case 'p':
      playSong();
      break;
  }
}

// ===== huru.pdeから移植：スペクトラム・歌詞・波形描画関数 =====

void updateSpectrum() {
  for (int i = 0; i < numBands; i++) {
    int index = int(map(i, 0, numBands, 0, fft.specSize()));
    float value = fft.getBand(index);
    bandValues[i] = 20 * log(value + 1);
    bandValues[i] = constrain(bandValues[i], minDB, maxDB);
  }
}

void drawWaveform() {
  stroke(100, 200, 255);
  noFill();

  beginShape();
  for (int i = 0; i < out.bufferSize() - 1; i += 4) {
    float x = map(i, 0, out.bufferSize(), 0, width);
    float y = 180 + out.left.get(i) * 80;
    vertex(x, y);
  }
  endShape();
}

void drawLyrics() {
  // 背景
  fill(30, 30, 50);
  noStroke();
  rect(20, 380, width - 40, 80, 10);

  // 星
  drawStars();

  // 歌詞（カラオケ風）
  drawKaraokeText(
    lyrics[currentLyricIndex],
    lyricProgress
  );

  // タイトル
  textAlign(LEFT, BASELINE);
  fill(200);
  textSize(12);
  text("Lyrics Display", 30, 378);
}

void updateLyricIndex() {
  if (songStartTime < 0) return;

  if (songPlaying) {
    float elapsed =
      (millis() - songStartTime) / 1000.0;

    float progress =
      elapsed / songTotalDuration;

    int idx =
      (int)(progress * lyrics.length);

    currentLyricIndex =
      constrain(idx, 0, lyrics.length - 1);

    // カラオケ用進行率
    float segment =
      songTotalDuration / lyrics.length;

    lyricProgress =
      (elapsed % segment) / (segment * 0.8);

    lyricProgress =
      constrain(lyricProgress, 0, 1);

    if (elapsed > songTotalDuration) {
      songPlaying = false;
      currentLyricIndex = lyrics.length - 1;
      lyricProgress = 1;
    }
  }
}

void drawVerticalAxis() {
  fill(200);
  textSize(10);
  textAlign(RIGHT, CENTER);

  for (float db = minDB; db <= maxDB; db += 10) {
    float y = map(db, minDB, maxDB, graphY + graphHeight, graphY);
    text((int)db + " dB", graphX - 10, y);
    stroke(40);
    line(graphX, y, graphX + graphWidth, y);
  }
  textAlign(LEFT, BASELINE);
}

void drawSpectrum() {
  stroke(150);
  noFill();
  rect(graphX, graphY, graphWidth, graphHeight);

  float barWidth = graphWidth / (float)numBands;

  for (int i = 0; i < numBands; i++) {
    float x = graphX + i * barWidth;
    float barHeight = map(bandValues[i], minDB, maxDB, 0, graphHeight);
    barHeight = constrain(barHeight, 0, graphHeight);

    float r = map(i, 0, numBands - 1, 50, 255);
    float g = map(barHeight, 0, graphHeight, 80, 220);
    float b = map(i, 0, numBands - 1, 255, 80);

    fill(r, g, b);
    noStroke();
    rect(x + 5, graphY + graphHeight - barHeight, barWidth - 10, barHeight);
  }
}

void drawFrequencyLabels() {
  fill(150);
  textSize(10);
  textAlign(CENTER);

  float barWidth = graphWidth / (float)numBands;

  for (int i = 0; i < numBands; i++) {
    float x = graphX + i * barWidth + barWidth / 2;
    text(((44100 / 2 / numBands) * (i + 1)) + "Hz", x,
         graphY + graphHeight + 15);
  }
  textAlign(LEFT, BASELINE);
}

void drawStars() {
  for (int i = 0; i < STAR_NUM; i++) {
    float brightness =
      180 + 75 * sin(frameCount * 0.05 + i);

    fill(255, 255, brightness);
    noStroke();

    ellipse(starX[i], starY[i], starSize[i], starSize[i]);

    // 少しずつ左へ流す
    starX[i] -= starSpeed[i];

    if (starX[i] < 20) {
      starX[i] = width - 20;
      starY[i] = random(380, 460);
    }
  }
}

void drawKaraokeText(
  String lyric,
  float progress
) {
  textSize(32);
  textAlign(CENTER, CENTER);

  float tw = textWidth(lyric);

  float leftX =
    width/2 - tw/2;

  float y = 420;

  // 白文字
  fill(255);
  text(lyric, width/2, y);

  // 黄色部分（カラオケ進行）
  push();

  float revealWidth =
    tw * progress;

  clip(
    (int)leftX,
    (int)(y - 30),
    (int)revealWidth,
    60
  );

  fill(255,255,0);
  text(lyric, width/2, y);

  noClip();

  pop();
}
