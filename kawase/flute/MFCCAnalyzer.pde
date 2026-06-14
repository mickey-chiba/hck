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
  // 画面にMFCCバーを描画する
void draw() {
  if (!hasResult) {
    fill(180);
    noStroke();
    textSize(13);
    text("Press 'm' to analyze MFCC", drawX + 10, drawY + 20);
    return;
  }

  // ── 係数ごとの意味ラベルと表示スケール ──────────────
  // 各係数が主に何を表すかの説明
  String[] labels = {
    "Energy",    // c1:  全体エネルギー
    "Bright",    // c2:  明暗（低域vs高域）
    "Round",     // c3:  丸み
    "Hard",      // c4:  硬さ
    "Sharp",     // c5:  鋭さ
    "Harm.1",    // c6:  第1倍音
    "Harm.2",    // c7:  第2倍音
    "Harm.3",    // c8:  第3倍音
    "Harm.4",    // c9:  第4倍音
    "Harm.5",    // c10: 第5倍音
    "Harm.6",    // c11: 第6倍音
    "Harm.7",    // c12: 第7倍音
    "Harm.8"     // c13: 第8倍音
  };

  // 係数ごとに適切な表示スケールを設定（値の大きさが違うため）
  float[] scales = {
    1.5,   // c1: 値が大きい（-30〜-50付近）ので小さめに
    8.0,   // c2: 値が中程度
    6.0,   // c3
    6.0,   // c4
    10.0,  // c5: 値が小さい
    15.0,  // c6
    15.0,  // c7
    15.0,  // c8
    15.0,  // c9
    15.0,  // c10
    10.0,  // c11
    8.0,   // c12
    20.0   // c13
  };

  // ── バーグラフ描画 ──────────────────────────────────
  int barW  = 26;
  int gap   = 6;
  int baseY = drawY + 110;

  // タイトル
  fill(255);
  noStroke();
  textSize(12);
  textAlign(LEFT);
  text("MFCC Coefficient Viewer", drawX + 10, drawY + 14);

  for (int k = 0; k < numCoeffs; k++) {
    float val    = mfcc[k];
    float scaled = constrain(val * scales[k], -90, 90);
    int   x      = drawX + 10 + k * (barW + gap);

    // バーの色：正→青系、負→赤系
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

    // 係数番号
    fill(160);
    textSize(9);
    textAlign(CENTER);
    text("c" + (k + 1), x + barW / 2, baseY + 12);

    // 意味ラベル（係数番号の下）
    fill(220);
    textSize(9);
    text(labels[k], x + barW / 2, baseY + 24);
  }

  // 基準線
  stroke(80);
  line(drawX + 10, baseY, drawX + 10 + numCoeffs * (barW + gap), baseY);

  // ── 数値テーブル（右側に縦並び） ───────────────────
  int tableX = drawX + numCoeffs * (barW + gap) + 20;
  int tableY = drawY + 14;

  fill(180);
  textSize(10);
  textAlign(LEFT);
  noStroke();
  text("coef   val    meaning", tableX, tableY);

  for (int k = 0; k < numCoeffs; k++) {
    // 値の大きさで色を変える
    float absVal = abs(mfcc[k]);
    if (absVal > 20) {
      fill(255, 200, 80);   // 大きい値：黄色
    } else if (absVal > 5) {
      fill(180, 220, 255);  // 中程度：水色
    } else {
      fill(160, 160, 160);  // 小さい値：グレー
    }
    text(
      "c" + nf(k+1, 2) + "  " + nf(mfcc[k], 3, 1) + "  " + labels[k],
      tableX,
      tableY + 16 + k * 14
    );
  }

  // ── 楽器判定結果 ──────────────────────────────────
  if (hasResult) {
    int resultY = drawY + 230;
    fill(255, 220, 50);
    textSize(13);
    textAlign(LEFT);
    noStroke();
    text("→ Closest: " + closestInstrument(), drawX + 10, resultY);

    // 4楽器の距離バー
    String[] instLabels = { "Flute", "Trumpet", "D.Bass", "Glockn" };
    float[]  dists = {
      euclideanDist(FLUTE_REFERENCE),
      euclideanDist(TRUMPET_REFERENCE),
      euclideanDist(DOUBLE_BASS_REFERENCE),
      euclideanDist(GLOCKENSPIEL_REFERENCE)
    };
    float maxDist = max(max(dists[0], dists[1]), max(dists[2], dists[3]));

    for (int i = 0; i < 4; i++) {
      int bx    = drawX + 10 + i * 110;
      int by    = resultY + 16;
      float ratio = dists[i] / max(maxDist, 1);
      int barLen  = (int)(ratio * 90);

      // 背景
      fill(50);
      noStroke();
      rect(bx, by, 90, 10, 2);

      // 距離バー（短いほど近い＝良い）
      fill(lerpColor(color(80, 200, 80), color(200, 80, 80), ratio));
      rect(bx, by, barLen, 10, 2);

      fill(200);
      textSize(9);
      textAlign(LEFT);
      text(instLabels[i], bx, by + 22);
      text(nf(dists[i], 1, 1), bx, by + 33);
    }
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

  // 指定した参照ベクトルとのユークリッド距離を返す
  float euclideanDist(float[] reference) {
    float dist = 0;
    for (int i = 0; i < numCoeffs; i++) {
      float diff = mfcc[i] - reference[i];
      dist += diff * diff;
    }
    return sqrt(dist);
  }

  // 4楽器との距離を計算して最も近い楽器名を返す
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
}