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

  // --- 内部状態 ---
  float[] mfcc;                  // 計算結果 (numCoeffs個)
  boolean hasResult = false;     // 計算済みフラグ
  float[] lastBuffer;            // 解析対象のバッファ

  // メルフィルタバンクの係数（初期化時に一度だけ計算）
  float[][] melFilters;

  // 描画位置
  int drawX = 0;
  int drawY = 200;   // 波形表示の下に配置

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
  void draw() {
    if (!hasResult) {
      fill(180);
      noStroke();
      textSize(13);
      text("Press 'm' to analyze MFCC", drawX + 10, drawY + 20);
      return;
    }

    // タイトル
    fill(255);
    noStroke();
    textSize(13);
    text("MFCC  (coefficients 1–" + numCoeffs + ")", drawX + 10, drawY + 16);

    // 各係数をバーグラフで表示
    int barW   = 24;
    int gap    = 4;
    int baseY  = drawY + 120;  // バーの基準線 Y

    for (int k = 0; k < numCoeffs; k++) {
      float val    = mfcc[k];
      float scaled = constrain(val * 2.0, -100, 100);  // 表示スケール調整
      int   x      = drawX + 10 + k * (barW + gap);

      // バーの色: 正→青系, 負→赤系
      if (val >= 0) {
        fill(60, 160, 255, 200);
      } else {
        fill(255, 80, 80, 200);
      }
      noStroke();

      // 正の値は上方向、負の値は下方向に描画
      if (scaled >= 0) {
        rect(x, baseY - scaled, barW, scaled);
      } else {
        rect(x, baseY, barW, -scaled);
      }

      // 数値ラベル（係数番号）
      fill(200);
      textSize(10);
      textAlign(CENTER);
      text(k + 1, x + barW / 2, baseY + 14);
    }

    // 基準線
    stroke(100);
    line(drawX + 10, baseY, drawX + 10 + numCoeffs * (barW + gap), baseY);

    // 数値読み上げ (係数1～4)
    fill(200);
    noStroke();
    textAlign(LEFT);
    textSize(11);
    for (int k = 0; k < min(4, numCoeffs); k++) {
      text("c" + (k+1) + ": " + nf(mfcc[k], 1, 2),
           drawX + 10 + k * 90, drawY + 170);
    }
  }

  // ── 内部計算 ──────────────────────────────────────

  // メルフィルタバンク行列を構築する
  // 戻り値: melFilters[filter_index][fft_bin_index]
  float[][] buildMelFilterBank() {
    float melMin = hzToMel(fMin);
    float melMax = hzToMel(fMax);

    // フィルタ中心周波数をメルスケールで等間隔に配置
    float[] melPoints = new float[numFilters + 2];
    for (int i = 0; i <= numFilters + 1; i++) {
      melPoints[i] = melMin + i * (melMax - melMin) / (numFilters + 1);
    }

    // メルスケールの中心点をHz→FFTビンに変換
    int[] binPoints = new int[numFilters + 2];
    for (int i = 0; i <= numFilters + 1; i++) {
      float hz = melToHz(melPoints[i]);
      binPoints[i] = round(hz * fftSize / sampleRate);
      binPoints[i] = constrain(binPoints[i], 0, fftSize / 2);
    }

    // 三角フィルタを構築
    float[][] filters = new float[numFilters][fftSize / 2 + 1];
    for (int m = 0; m < numFilters; m++) {
      int left   = binPoints[m];
      int center = binPoints[m + 1];
      int right  = binPoints[m + 2];

      for (int k = left; k < center; k++) {
        if (center != left) {
          filters[m][k] = (float)(k - left) / (center - left);
        }
      }
      for (int k = center; k <= right; k++) {
        if (right != center) {
          filters[m][k] = (float)(right - k) / (right - center);
        }
      }
    }
    return filters;
  }

  // MFCC本体の計算
  float[] computeMFCC(float[] signal) {
    int N = signal.length;

    // (1) ハミング窓を適用
    float[] windowed = new float[N];
    for (int i = 0; i < N; i++) {
      windowed[i] = signal[i] * (0.54 - 0.46 * cos(TWO_PI * i / (N - 1)));
    }

    // (2) FFT（実数FFT：Processing組み込みはないため自前DFTで代用）
    //     計算量削減のため半分のビン数のみ計算
    int halfN = N / 2 + 1;
    float[] power = new float[halfN];
    for (int k = 0; k < halfN; k++) {
      float re = 0, im = 0;
      for (int n = 0; n < N; n++) {
        float angle = TWO_PI * k * n / N;
        re += windowed[n] * cos(angle);
        im -= windowed[n] * sin(angle);
      }
      power[k] = re * re + im * im;  // パワースペクトル
    }

    // (3) メルフィルタバンクを適用 → 対数
    float[] logMelEnergy = new float[numFilters];
    for (int m = 0; m < numFilters; m++) {
      float energy = 0;
      for (int k = 0; k < halfN; k++) {
        energy += melFilters[m][k] * power[k];
      }
      logMelEnergy[m] = log(max(energy, 1e-10));
    }

    // (4) DCT-II でメル対数エネルギー → MFCC
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

  // Hz → メルスケール変換
  float hzToMel(float hz) {
    return 2595.0 * log10(1.0 + hz / 700.0);
  }

  // メルスケール → Hz 変換
  float melToHz(float mel) {
    return 700.0 * (pow(10.0, mel / 2595.0) - 1.0);
  }

  // log10 ヘルパー
  float log10(float x) {
    return log(x) / log(10.0);
  }
}