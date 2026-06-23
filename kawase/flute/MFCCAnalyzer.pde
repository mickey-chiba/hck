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
  int drawY = 180;   // 波形表示の下に配置

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

// ----------------------変更点---------------------
// 音量変化も評価に入れたい:i = 0/評価に入れたくない:i = 1
  float euclideanDist(float[] reference) {
    float dist = 0;
    for (int i = 1; i < numCoeffs; i++) {
      float diff = mfcc[i] - reference[i];
      dist += diff * diff;
    }
    return sqrt(dist);
  }
// ---------------------------------------------------

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