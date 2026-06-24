import ddf.minim.*;
import ddf.minim.ugens.*;
import ddf.minim.analysis.*;
import processing.serial.*;

AudioOutput out;
Minim minim;
InstrumentModule flute;
MFCCAnalyzer mfccAnalyzer;

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
String[] lyrics = {"きらきら ひかる", "おそらの ほしよ"};
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

// 各音の高さ
String [] melody = {
  "C3","C3","G2","G2","A2","A2","G2","F2","F2","E2","E2","D2","D2","C2"
};

// 各音の長さ（拍）
float [] duration = {
  0.9f, 0.9f, 0.9f,0.9f, 0.9f, 0.9f,2.5f, 0.9f, 0.9f, 0.9f,0.9f, 0.9f, 0.9f, 0.9f
};

// 各音の開始位置
float [] startTime = {
  0.0f, 1.0f, 2.0f,3.0f, 4.0f, 5.0f,6.0f, 8.0f, 9.0f, 10.0f,11.0f, 12.0f, 13.0f, 14.0f
};

// 各音の音量
float[] amplitudes = {
  0.5f, 0.5f, 0.5f, 0.5f,0.5f, 0.5f, 0.5f, 0.5f,0.5f, 0.5f, 0.5f, 0.5f,0.5f, 0.5f
};

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
  out = minim.getLineOut(Minim.STEREO, 1024);
  pixelDensity(1);
  mfccAnalyzer = new MFCCAnalyzer();

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

  // MFCC描画
  mfccAnalyzer.draw();

  // タイトル
  fill(255);
  textSize(14);
  textAlign(LEFT, BASELINE);
  text("Waveform (Time Domain)", 20, 35);
  text("FFT Spectrum", 20, graphY - 20);

  fill(255,255,180);
  textSize(30);
  textAlign(CENTER);
  text("♫ きらきら星 (コントラバス)", width/2, 80);

  // FPS表示
  fill(255);
  textSize(20);
  textAlign(RIGHT);
  text("FPS: " + nf(frameRate, 0, 1), width - 30, 40);
  textAlign(LEFT, BASELINE);
}

void playSong() {
  out.pauseNotes();

  // 歌詞再生開始
  songStartTime = millis();
  songPlaying = true;
  currentLyricIndex = 0;

  for (int i = 0; i < melody.length; i++) {
    InstrumentConfig bass = new InstrumentConfig();

    bass.out = out;
    bass.waves = new String[] { "SINE", "TRIANGLE" };

    // melody[i] の音階名を周波数に変換して、この音の基音にする
    bass.baseFreq = Frequency.ofPitch(melody[i]).asHz();
    

    bass.harmonics = new float[] {1.0, 0.3 };
    bass.cutoff = 800.0;
    bass.res = 0.05;
    bass.filterMode = 0;
    bass.fcoRate = 0.0;
    bass.fcoAmount = 0.0;

    // amplitudes[i] を使って、音ごとの強弱を変える
    bass.vol = 2.2;

    bass.atk = 0.005;
    bass.dec = 0.3;
    bass.sus = 0.15;
    bass.rel = 0.6;

    out.playNote(
      startTime[i],
      duration[i],
      new InstrumentModule(bass)
    );
  }

  out.resumeNotes();
}

void keyPressed() {
  switch (key) {
    case 'p':
      playSong();
      break;
      
      case 'm':
      mfccAnalyzer.analyze(out);
      break;
  }
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
}

// MFCCAnalyzer.pde
// MFCC計算 + 画面描画を担うクラス

class MFCCAnalyzer {

  // --- パラメータ ---
  int    sampleRate  = 44100;
  int    numCoeffs   = 13;       // 取得するMFCC係数の数
  int    numFilters  = 26;       // メルフィルタバンクの数
  int    fftSize     = 1024;     // FFTサイズ（out.bufferSize() と合わせる）
  float  fMin        = 80.0;     // メルフィルタの最低周波数 [Hz]
  float  fMax        = 8000.0;   // メルフィルタの最高周波数 [Hz]

  // ★ここに追加：4楽器の参照MFCCベクトル
  float[] FLUTE_REFERENCE        = { -31.891,  4.254, -6.496, -4.856, -2.536, -0.928,  0.806,  1.620,  1.759,  2.030, -2.750, -5.330, -0.970 };
  float[] TRUMPET_REFERENCE      = { -26.425,  7.932, -3.136, -1.621, -2.259, -2.458, -2.232, -2.016, -1.765, -1.816, -2.001, -1.551, -0.168 };
  float[] DOUBLE_BASS_REFERENCE  = { -31.206, 12.254,  5.792,  4.162,  2.809,  1.850,  1.334,  0.778,  0.158,  0.259,  0.153,  0.059,  0.091 };
  float[] GLOCKENSPIEL_REFERENCE = { -48.173,  3.430, -1.275,  0.197,  3.776,  1.625,  0.359,  0.523, -0.370,  0.387,  0.527,  0.861,  0.000 };

  // --- 内部状態 ---
  float[] mfcc;                  // 計算結果 (numCoeffs個)
  boolean hasResult = false;     // 計算済みフラグ
  float[] lastBuffer;            // 解析対象のバッファ

  // メルフィルタバンクの係数（初期化時に一度だけ計算）
  float[][] melFilters;

  // 描画位置
  int drawX = 0;
  int drawY = 500;   // 歌詞・波形表示の下に配置

  MFCCAnalyzer() {
    mfcc       = new float[numCoeffs];
    melFilters = buildMelFilterBank();
  }

  // ── 公開メソッド ──────────────────────────────────

  // AudioOutput の左チャンネルバッファからMFCCを計算する
  void analyze(AudioOutput out) {
    int n = min(out.bufferSize(), fftSize);
    float[] buf = new float[fftSize];
    for (int i = 0; i < n; i++) {
      buf[i] = out.left.get(i);
    }
    lastBuffer = buf;
    mfcc       = computeMFCC(buf);
    hasResult  = true;
  }

  // 画面にMFCCバーを描画する
  // 画面にMFCCバーを描画する
void draw() {
  if (!hasResult) {
    fill(180);
    noStroke();
    textSize(13);
    text("Press 'm' to analyze MFCC", drawX + 10, drawY + 20);
    return;
  }

  String[] labels = {
    "Energy", "Bright", "Round", "Hard", "Sharp",
    "Harm.1", "Harm.2", "Harm.3", "Harm.4",
    "Harm.5", "Harm.6", "Harm.7", "Harm.8"
  };

  float[] scales = {
    1.5, 8.0, 6.0, 6.0, 10.0,
    15.0, 15.0, 15.0, 15.0,
    15.0, 10.0, 8.0, 20.0
  };

  // ── タイトル ──────────────────────────────────────
  fill(255);
  noStroke();
  textSize(14);
  textAlign(LEFT);
  text("MFCC Coefficient Viewer", drawX + 10, drawY + 18);

  // ── バーグラフ ────────────────────────────────────
  int barW  = 42;   // バー幅
  int gap   = 8;    // バー間隔
  int baseY = drawY + 100;

  for (int k = 0; k < numCoeffs; k++) {
    float val    = mfcc[k];
    float scaled = constrain(val * scales[k], -70, 70);
    int   x      = drawX + 10 + k * (barW + gap);

    if (val >= 0) {
      fill(60, 160, 255, 210);
    } else {
      fill(255, 80, 80, 210);
    }
    noStroke();

    if (scaled >= 0) {
      rect(x, baseY - scaled, barW, scaled, 3);
    } else {
      rect(x, baseY, barW, -scaled, 3);
    }

    // 係数番号（バーの下）
    fill(160);
    textSize(12);    // ★ 大きく
    textAlign(CENTER);
    text("c" + (k + 1), x + barW / 2, baseY + 18);

    // 意味ラベル（係数番号の下）
    fill(220);
    textSize(12);    // ★ 大きく
    text(labels[k],     x + barW / 2, baseY + 34);
  }

  // 基準線
  stroke(80);
  line(drawX + 10, baseY, drawX + 10 + numCoeffs * (barW + gap), baseY);

  // ── 数値テーブル（バーグラフの下、横並び） ──────────
  int tableY = baseY + 130;

  fill(180);
  noStroke();
  textSize(13);
  textAlign(LEFT);
  text("coef   val      meaning", drawX + 10, tableY);

  // 2列に分けて表示（左7個・右6個）
  for (int k = 0; k < numCoeffs; k++) {
    float absVal = abs(mfcc[k]);
    if (absVal > 20) {
      fill(255, 200, 80);
    } else if (absVal > 5) {
      fill(180, 220, 255);
    } else {
      fill(160, 160, 160);
    }

    int col  = k / 7;          // 0列目 or 1列目
    int row  = k % 7;          // 列内の行番号
    int tx   = drawX + 10 + col * 330;
    int ty   = tableY + 20 + row * 22;

    textSize(15);              // ★ 大きく
    textAlign(LEFT);
    text("c" + nf(k+1, 2) + "   " + nf(mfcc[k], 3, 1) + "   " + labels[k], tx, ty);
  }

  // ── 楽器判定結果 ──────────────────────────────────
  int resultY = tableY + 20 + 7 * 22 + 20;

  fill(255, 220, 50);
  textSize(18);
  textAlign(LEFT);
  noStroke();
  text("→ Closest: " + closestInstrument(), drawX + 10, resultY);

  String[] instLabels = { "Flute", "Trumpet", "D.Bass", "Glockn" };
  float[]  dists = {
    euclideanDist(FLUTE_REFERENCE),
    euclideanDist(TRUMPET_REFERENCE),
    euclideanDist(DOUBLE_BASS_REFERENCE),
    euclideanDist(GLOCKENSPIEL_REFERENCE)
  };
  float maxDist = max(max(dists[0], dists[1]), max(dists[2], dists[3]));

  for (int i = 0; i < 4; i++) {
    int bx      = drawX + 10 + i * 160;
    int by      = resultY + 16;
    float ratio = dists[i] / max(maxDist, 1);
    int barLen  = (int)(ratio * 130);

    fill(50);
    noStroke();
    rect(bx, by, 130, 14, 2);

    fill(lerpColor(color(80, 200, 80), color(200, 80, 80), ratio));
    rect(bx, by, barLen, 14, 2);

    fill(200);
    textSize(15);
    textAlign(LEFT);
    text(instLabels[i], bx, by + 28);
    text(nf(dists[i], 1, 1), bx, by + 46);
  }
}

// ── 内部計算 ──────────────────────────────────────

  float[][] buildMelFilterBank() {
    float melMin = hzToMel(fMin);
    float melMax = hzToMel(fMax);
    float[] melPoints = new float[numFilters + 2];
    for (int i = 0; i <= numFilters + 1; i++) {
      melPoints[i] = melMin + i * (melMax - melMin) / (numFilters + 1);
    }
    int[] binPoints = new int[numFilters + 2];
    for (int i = 0; i <= numFilters + 1; i++) {
      float hz = melToHz(melPoints[i]);
      binPoints[i] = round(hz * fftSize / sampleRate);
      binPoints[i] = constrain(binPoints[i], 0, fftSize / 2);
    }
    float[][] filters = new float[numFilters][fftSize / 2 + 1];
    for (int m = 0; m < numFilters; m++) {
      int left   = binPoints[m];
      int center = binPoints[m + 1];
      int right  = binPoints[m + 2];
      for (int k = left; k < center; k++) {
        if (center != left) filters[m][k] = (float)(k - left) / (center - left);
      }
      for (int k = center; k <= right; k++) {
        if (right != center) filters[m][k] = (float)(right - k) / (right - center);
      }
    }
    return filters;
  }

  float[] computeMFCC(float[] signal) {
    int N = signal.length;
    float[] windowed = new float[N];
    for (int i = 0; i < N; i++) {
      windowed[i] = signal[i] * (0.54 - 0.46 * cos(TWO_PI * i / (N - 1)));
    }
    int halfN = N / 2 + 1;
    float[] power = new float[halfN];
    for (int k = 0; k < halfN; k++) {
      float re = 0, im = 0;
      for (int n = 0; n < N; n++) {
        float angle = TWO_PI * k * n / N;
        re += windowed[n] * cos(angle);
        im -= windowed[n] * sin(angle);
      }
      power[k] = re * re + im * im;
    }
    float[] logMelEnergy = new float[numFilters];
    for (int m = 0; m < numFilters; m++) {
      float energy = 0;
      for (int k = 0; k < halfN; k++) {
        energy += melFilters[m][k] * power[k];
      }
      logMelEnergy[m] = log(max(energy, 1e-10));
    }
    float[] coeffs = new float[numCoeffs];
    for (int i = 0; i < numCoeffs; i++) {
      float sum = 0;
      for (int m = 0; m < numFilters; m++) {
        sum += logMelEnergy[m] * cos(PI * i * (m + 0.5) / numFilters);
      }
      coeffs[i] = sum;
    }
    return coeffs;
  }

  float hzToMel(float hz) {
    return 2595.0 * log10(1.0 + hz / 700.0);
  }

  float melToHz(float mel) {
    return 700.0 * (pow(10.0, mel / 2595.0) - 1.0);
  }

  float log10(float x) {
    return log(x) / log(10.0);
  }

  float euclideanDist(float[] reference) {
    float dist = 0;
    for (int i = 0; i < numCoeffs; i++) {
      float diff = mfcc[i] - reference[i];
      dist += diff * diff;
    }
    return sqrt(dist);
  }

  String closestInstrument() {
    if (!hasResult) return "---";
    float dF = euclideanDist(FLUTE_REFERENCE);
    float dT = euclideanDist(TRUMPET_REFERENCE);
    float dD = euclideanDist(DOUBLE_BASS_REFERENCE);
    float dG = euclideanDist(GLOCKENSPIEL_REFERENCE);
    float minD = min(min(dF, dT), min(dD, dG));
    if      (minD == dF) return "Flute        dist:" + nf(dF,1,1);
    else if (minD == dT) return "Trumpet      dist:" + nf(dT,1,1);
    else if (minD == dD) return "Double Bass  dist:" + nf(dD,1,1);
    else                 return "Glockenspiel dist:" + nf(dG,1,1);
  }

} // ← クラスの閉じ括弧

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
        float[] partials = {1.0,2.0,3.0};

        float freq = baseFreq * partials[i];

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