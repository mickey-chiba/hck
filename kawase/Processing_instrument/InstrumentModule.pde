// ============================================================
// 音色合成エンジン
// InstrumentConfig: 音色パラメータをまとめるデータクラス
// InstrumentModule: Minimのオシレーター・フィルター・ADSRを
//                   組み合わせて音を合成するクラス
// ============================================================

// 音色設定用のパラメータオブジェクト
class InstrumentConfig {
  AudioOutput out;

  String[] waves;    // 使用する波形名の配列（"SINE", "SAW", "SQUARE", "TRIANGLE"）
  float baseFreq;    // 基音の周波数（Hz）
  float[] harmonics; // 倍音ごとの音量比

  float cutoff;      // ローパスフィルターのカットオフ周波数（Hz）
  float res;         // フィルターのレゾナンス（0〜1）
  int filterMode;    // フィルター種別: 0=LP, 1=HP, 2=BP

  float fcoRate;     // フィルターカットオフを揺らす速さ（Hz）、0で無効
  float fcoAmount;   // フィルターカットオフの揺れ幅（Hz）

  float vol;         // 音量（0〜1）
  float atk;         // アタック時間（秒）
  float dec;         // ディケイ時間（秒）
  float sus;         // サステインレベル（0〜1）
  float rel;         // リリース時間（秒）

  float vibratoRate  = 0.0; // ビブラートの速さ（Hz）、0で無効
  float vibratoDepth = 0.0; // ビブラートの揺れ幅（Hz）
}

// 楽器モジュール: Minimの Instrument として使えるように implements Instrument を付ける
class InstrumentModule implements Instrument {
  AudioOutput _out;
  Summer      _summer; // 複数のOscilをまとめるミキサー
  Oscil[]     _waves;  // 倍音ごとのオシレーター配列
  Oscil       _fco;    // フィルターカットオフを揺らすオシレーター
  MoogFilter  _filter; // 音色を整形するフィルター
  ADSR        _adsr;   // 音の包絡線（Attack/Decay/Sustain/Release）
  Oscil       _vibrato; // ビブラート用オシレーター

  // コンストラクタ: InstrumentConfigを受け取って音を組み立てる
  InstrumentModule(InstrumentConfig config) {
    _out = config.out;

    String[] waves    = config.waves;
    float baseFreq    = config.baseFreq;
    float[] harmonics = config.harmonics;

    // 波形が指定されていない場合はSINE波にする
    if (waves == null || waves.length == 0) {
      waves = new String[] { "SINE" };
    }

    // 倍音が指定されていない場合は基音のみにする
    if (harmonics == null || harmonics.length == 0) {
      harmonics = new float[] { 1.0 };
    }

    _summer = new Summer();

    // 波形数 × 倍音数 分のOscilを作成する
    int waveTotal = waves.length * harmonics.length;
    _waves = new Oscil[waveTotal];
    int index = 0;

    for (int w = 0; w < waves.length; w++) {
      Waveform waveform = getWaveform(waves[w]);

      for (int i = 0; i < harmonics.length; i++) {
        // 基音の i+1 倍の周波数で倍音を作る
        float freq = baseFreq * (i + 1);
        // 複数波形を足すと音量が大きくなりすぎるので波形数で割る
        float amp = config.vol * harmonics[i] / waves.length;

        _waves[index] = new Oscil(freq, amp, waveform);
        _waves[index].patch(_summer);
        index++;
      }
    }

    // フィルターを作成（filterModeでLP/HP/BPを切り替える）
    _filter = new MoogFilter(
      config.cutoff,
      config.res,
      getFilterType(config.filterMode)
    );

    // FCO: フィルターのカットオフ周波数を周期的に揺らす
    if (config.fcoRate > 0 && config.fcoAmount > 0) {
      _fco = new Oscil(config.fcoRate, config.fcoAmount, Waves.SINE);
      _fco.offset.setLastValue(config.cutoff);
      _fco.patch(_filter.frequency);
    }

    // ビブラート: 各オシレーターの周波数を揺らす
    if (config.vibratoRate > 0 && config.vibratoDepth > 0) {
      for (int i = 0; i < _waves.length; i++) {
        float freq = _waves[i].frequency.getLastValue();
        // 倍音ごとに揺れ幅を周波数比で調整する
        float scaledDepth = config.vibratoDepth * (freq / config.baseFreq);
        _vibrato = new Oscil(config.vibratoRate, scaledDepth, Waves.SINE);
        _vibrato.offset.setLastValue(freq);
        _vibrato.patch(_waves[i].frequency);
      }
    }

    _adsr = new ADSR(config.vol, config.atk, config.dec, config.sus, config.rel);

    // 信号の流れ: Oscilたち → Summer → Filter → ADSR → 出力
    _summer.patch(_filter).patch(_adsr).patch(_out);
  }

  // 文字列の波形名をMinimのWaveformオブジェクトに変換する
  Waveform getWaveform(String wave) {
    if (wave == null) return Waves.SINE;
    wave = wave.toUpperCase();
    if (wave.equals("SINE"))     return Waves.SINE;
    if (wave.equals("SAW"))      return Waves.SAW;
    if (wave.equals("SQUARE"))   return Waves.SQUARE;
    if (wave.equals("TRIANGLE")) return Waves.TRIANGLE;
    return Waves.SINE; // 不明な指定はSINEにフォールバック
  }

  // 数値のフィルター種別をMoogFilter.Typeに変換する
  MoogFilter.Type getFilterType(int filterMode) {
    if (filterMode == 0) return MoogFilter.Type.LP; // ローパス
    if (filterMode == 1) return MoogFilter.Type.HP; // ハイパス
    if (filterMode == 2) return MoogFilter.Type.BP; // バンドパス
    return MoogFilter.Type.LP;
  }

  // 発音開始（Minimから呼ばれる）
  void noteOn(float duration) {
    _adsr.noteOn();
  }

  // 発音終了（Minimから呼ばれる）
  void noteOff() {
    _adsr.noteOff();
    _adsr.unpatchAfterRelease(_out); // リリース完了後に出力から切り離す
  }
}
