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

  // ↓ 追加
  float vibratoRate  = 0.0; // 揺れる速さ (Hz) 0で無効
  float vibratoDepth = 0.0; // 揺れ幅 (Hz)
}

// 楽器モジュール (クラス) の設計図
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

    // ↓ FCOブロックの後ろに追加
    // ビブラート：各オシレーターの周波数を揺らす
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