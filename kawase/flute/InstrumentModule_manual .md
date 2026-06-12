# InstrumentModule マニュアル

`InstrumentModule` は、Processing + Minim で音色を作るための楽器モジュールです。

複数の波形、倍音、フィルター、FCO、ADSR を組み合わせて、シンセサイザーのように音を作ることができます。

このバージョンでは、音色の設定を `InstrumentConfig` というパラメータオブジェクトにまとめてから、`InstrumentModule` に渡します。

---

## できること

`InstrumentModule` では、以下の要素を組み合わせて音色を作れます。

- 複数の波形を重ねる
- 倍音の量を調整する
- フィルターをかける
- FCOでフィルターのカットオフ周波数を揺らす
- ADSRで音の立ち上がりや余韻を調整する
- `baseFreq` を変えることで、同じ音色のまま違う音階を鳴らす

---

## 基本的な使い方

まず `InstrumentConfig` を作り、音色の設定を入れます。

```java
InstrumentConfig config = new InstrumentConfig();

config.out = out;
config.waves = new String[] { "SINE", "TRIANGLE" };
config.baseFreq = 440.0;
config.harmonics = new float[] { 1.0, 0.4, 0.2 };

config.cutoff = 6000.0;
config.res = 0.1;
config.filterMode = 0;

config.fcoRate = 0.0;
config.fcoAmount = 0.0;

config.vol = 0.7;
config.atk = 0.1;
config.dec = 0.3;
config.sus = 0.5;
config.rel = 0.5;
```

そのあと、`out.playNote()` の中で `new InstrumentModule(config)` を使います。

```java
out.playNote(0.0, 1.0, new InstrumentModule(config));
```

---

## InstrumentConfig の設定項目

| 項目 | 型 | 意味 |
|---|---|---|
| `out` | `AudioOutput` | 音の出力先 |
| `waves` | `String[]` | 使用する波形 |
| `baseFreq` | `float` | 基音の周波数 |
| `harmonics` | `float[]` | 倍音の音量バランス |
| `cutoff` | `float` | フィルターのカットオフ周波数 |
| `res` | `float` | レゾナンス |
| `filterMode` | `int` | フィルターの種類 |
| `fcoRate` | `float` | FCOの揺れる速さ |
| `fcoAmount` | `float` | FCOの揺れ幅 |
| `vol` | `float` | 全体の音量 |
| `atk` | `float` | 発音から最大音量になるまでの時間 |
| `dec` | `float` | 最大音量からSustain音量まで下がる時間 |
| `sus` | `float` | 最終的に保持される音量 |
| `rel` | `float` | 発音終了から音が完全に消えるまでの時間 |

---

## out：音の出力先

`out` は、Minim の `AudioOutput` です。

メインプログラム側で先に準備しておきます。

```java
Minim minim;
AudioOutput out;

void setup() {
  minim = new Minim(this);
  out = minim.getLineOut();
}
```

`InstrumentConfig` には必ず以下のように入れてください。

```java
config.out = out;
```

これを忘れると、音の出力先がないため音が鳴りません。

---

## waves：波形

`waves` では、使いたい波形を配列で指定します。

```java
config.waves = new String[] { "SINE", "TRIANGLE" };
```

使用できる波形は以下です。

| 指定する文字 | 音の特徴 |
|---|---|
| `"SINE"` | なめらかで丸い音 |
| `"TRIANGLE"` | 柔らかく、少し芯のある音 |
| `"SQUARE"` | 電子的で太い音 |
| `"SAW"` | 明るく鋭い音 |

複数指定すると、それらの波形が重なった音になります。

```java
config.waves = new String[] { "SINE", "SAW", "TRIANGLE" };
```

---

## baseFreq：基音の周波数

`baseFreq` は、音の高さを決める基本周波数です。

```java
config.baseFreq = 440.0;
```

音階名から周波数を作りたい場合は、Minim の `Frequency.ofPitch()` を使えます。

```java
config.baseFreq = Frequency.ofPitch("A4").asHz();
```

例えば `"A4"` は `440.0Hz` に変換されます。

---

## メロディ配列から baseFreq を設定する

`baseFreq` は1つの音の高さを表す値なので、メロディを鳴らす場合は、音ごとに `baseFreq` を変えた `InstrumentConfig` を作ります。

例えば、以下のような音階配列があるとします。

```java
String[] melody = {
  "A4", "D5", "C5", "G4", "A4", "C5", "G4"
};
```

この配列の音を順番に鳴らすには、`for` 文の中で

```java
flute.baseFreq = Frequency.ofPitch(melody[i]).asHz();
```

のように書きます。

これにより、`melody[i]` に入っている `"A4"` や `"D5"` が周波数に変換され、その音の基音として使われます。

---

## メロディ再生の例
再生の前に下準備として`startTime`、`duration`、`amplitudes` の配列を作成します。

`startTime[i]` は、その音を鳴らし始める位置です。

`duration[i]` は、その音の長さです。

`amplitudes[i]` は、その音の音量です。

はじめにやったProcessingの課題を思い出していただけると分かりやすいです。
以下のような感じで配列を用意します。

```java
// 各音の高さ
String [] melody = {
  "A4", "D5", "C5", "G4", "A4", "C5", "G4"
};

// 各音の長さ（拍）
float [] duration = {
  0.5f, 0.5f, 2.0f, 0.5f, 0.5f, 0.5f, 2.0f
};

// 各音の開始位置
float [] startTime = {
  0.0f, 0.5f, 1.0f, 3.0f, 3.5f, 4.0f, 4.5f
};

// 各音の音量
float[] amplitudes = {
  0.5f, 0.5f, 1.0f, 0.8f, 0.8f, 0.5f, 0.5f
};
```

作成した`melody`、`startTime`、`duration`、`amplitudes` の配列を使って、設定した楽器音でメロディを鳴らします。
それが以下の例です。

```java
void playSong() {
  out.pauseNotes();

  for (int i = 0; i < melody.length; i++) {
    InstrumentConfig flute = new InstrumentConfig();

    flute.out = out;
    flute.waves = new String[] { "SINE", "TRIANGLE" };

    // melody[i] の音階名を周波数に変換して、この音の基音にする
    flute.baseFreq = Frequency.ofPitch(melody[i]).asHz();

    flute.harmonics = new float[] { 1.0, 0.4, 0.2 };
    flute.cutoff = 6000.0;
    flute.res = 0.1;
    flute.filterMode = 0;
    flute.fcoRate = 0.0;
    flute.fcoAmount = 0.0;

    // amplitudes[i] を使って、音ごとの強弱を変える
    flute.vol = amplitudes[i];

    flute.atk = 0.2;
    flute.dec = 0.4;
    flute.sus = 0.5;
    flute.rel = 0.8;

    out.playNote(
      startTime[i],
      duration[i],
      new InstrumentModule(flute)
    );
  }

  out.resumeNotes();
}
```

`out.setTempo(120);` を使っている場合、`startTime` と `duration` は秒ではなく拍として扱われます。

```java
out.setTempo(120);
```

この場合、BPM 120 なので、1拍は `0.5秒` になります。


---

## harmonics：倍音

`harmonics` は、基音に対してどの倍音をどれくらい鳴らすかを決めます。

```java
config.harmonics = new float[] { 1.0, 0.4, 0.2 };
```

この場合、以下のような意味になります。

| 配列の位置 | 倍音 | 音量 |
|---|---|---|
| `0` | 1倍音 | `1.0` |
| `1` | 2倍音 | `0.4` |
| `2` | 3倍音 | `0.2` |

倍音を増やすと、音は複雑で明るくなります。

倍音を減らすと、音はシンプルで丸くなります。

---

## cutoff：カットオフ周波数

`cutoff` は、フィルターで音を削る基準になる周波数です。

```java
config.cutoff = 6000.0;
```

値を小さくすると、こもった音になりやすいです。

値を大きくすると、明るい音になりやすいです。

---

## res：レゾナンス

`res` は、カットオフ周波数付近を強調する量です。

```java
config.res = 0.3;
```

値を大きくすると、フィルターのクセが強くなります。

最初は `0.0` から `1.0` くらいで調整すると扱いやすいです。

---

## filterMode：フィルターの種類

`filterMode` は、数字でフィルターの種類を指定します。

| 値 | 種類 | 説明 |
|---|---|---|
| `0` | ローパスフィルター | 高い音を削り、丸い音にする |
| `1` | ハイパスフィルター | 低い音を削り、軽い音にする |
| `2` | バンドパスフィルター | 一部の帯域だけを通す |

例：

```java
config.filterMode = 0;
```

---

## fcoRate：FCOの速さ

FCOは、フィルターのカットオフ周波数を自動で揺らす機能です。

`fcoRate` は、その揺れの速さを指定します。

```java
config.fcoRate = 4.0;
```

値を大きくすると、フィルターの動きが速くなります。

FCOを使わない場合は `0.0` にします。

```java
config.fcoRate = 0.0;
```

---

## fcoAmount：FCOの揺れ幅

`fcoAmount` は、カットオフ周波数をどれくらい大きく揺らすかを指定します。

```java
config.fcoAmount = 2000.0;
```

例えば、

```java
config.cutoff = 6000.0;
config.fcoAmount = 2000.0;
```

の場合、カットオフ周波数はおおよそ以下の範囲で揺れます。

```text
4000Hz から 8000Hz
```

FCOを使わない場合は `0.0` にします。

```java
config.fcoAmount = 0.0;
```

---

## vol：音量

`vol` は、音全体の大きさです。

```java
config.vol = 0.7;
```

複数の波形や倍音を重ねると音が大きくなりやすいです。

音が割れる場合は、`vol` を小さくしてください。

```java
config.vol = 0.3;
```

---

## ADSRについて

ADSRは、音量の時間変化を作るための設定です。

```text
Attack  →  Decay  →  Sustain  →  Release
```

---

## atk：Attack

`atk` は、発音してから最大音量になるまでの時間です。

```java
config.atk = 0.05;
```

値が小さいと、すぐに音が鳴ります。

値が大きいと、ゆっくり音が立ち上がります。

---

## dec：Decay

`dec` は、最大音量からSustain音量まで下がる時間です。

```java
config.dec = 0.3;
```

---

## sus：Sustain

`sus` は、音を鳴らしている間に保たれる音量です。

```java
config.sus = 0.5;
```

`vol` に対する割合として考えるとわかりやすいです。

---

## rel：Release

`rel` は、音が終わったあと、完全に消えるまでの時間です。

```java
config.rel = 0.8;
```

値が小さいと、音はすぐに消えます。

値が大きいと、余韻が長く残ります。

---

# プログラムの例
最低限音は鳴るはずです。
見やすい設定は各自で行なってください。

```java
import ddf.minim.*;
import ddf.minim.ugens.*;
import processing.serial.*;

AudioOutput out;
Minim minim;
InstrumentModule flute;

// 各音の高さ
String [] melody = {
  "A4", "D5", "C5", "G4", "A4", "C5", "G4"
};

// 各音の長さ（拍）
float [] duration = {
  0.5f, 0.5f, 2.0f, 0.5f, 0.5f, 0.5f, 2.0f
};

// 各音の開始位置
float [] startTime = {
  0.0f, 0.5f, 1.0f, 3.0f, 3.5f, 4.0f, 4.5f
};

// 各音の音量
float[] amplitudes = {
  0.5f, 0.5f, 1.0f, 0.8f, 0.8f, 0.5f, 0.5f
};

void setup(){
  minim = new Minim(this);
  out = minim.getLineOut();
  out.setTempo( 120 );
}
void draw(){

}

void playSong() {
  out.pauseNotes();

  for (int i = 0; i < melody.length; i++) {
    InstrumentConfig flute = new InstrumentConfig();

    flute.out = out;
    flute.waves = new String[] { "SINE", "TRIANGLE" };

    // melody[i] の音階名を周波数に変換して、この音の基音にする
    flute.baseFreq = Frequency.ofPitch(melody[i]).asHz();

    flute.harmonics = new float[] { 1.0, 0.4, 0.2 };
    flute.cutoff = 6000.0;
    flute.res = 0.1;
    flute.filterMode = 0;
    flute.fcoRate = 0.0;
    flute.fcoAmount = 0.0;

    // amplitudes[i] を使って、音ごとの強弱を変える
    flute.vol = amplitudes[i];

    flute.atk = 0.2;
    flute.dec = 0.4;
    flute.sus = 0.5;
    flute.rel = 0.8;

    out.playNote(
      startTime[i],
      duration[i],
      new InstrumentModule(flute)
    );
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
```

---

# 音の作例

## 明るいシンセリード風

```java
InstrumentConfig lead = new InstrumentConfig();

lead.out = out;
lead.waves = new String[] { "SAW", "SQUARE" };
lead.baseFreq = 440.0;
lead.harmonics = new float[] { 1.0, 0.7, 0.4, 0.2 };

lead.cutoff = 5000.0;
lead.res = 0.4;
lead.filterMode = 0;

lead.fcoRate = 3.0;
lead.fcoAmount = 1500.0;

lead.vol = 0.6;
lead.atk = 0.02;
lead.dec = 0.2;
lead.sus = 0.4;
lead.rel = 0.3;

out.playNote(0.0, 1.0, new InstrumentModule(lead));
```

---

## こもったベース風

```java
InstrumentConfig bass = new InstrumentConfig();

bass.out = out;
bass.waves = new String[] { "SQUARE", "SAW" };
bass.baseFreq = 110.0;
bass.harmonics = new float[] { 1.0, 0.5, 0.2 };

bass.cutoff = 1200.0;
bass.res = 0.6;
bass.filterMode = 0;

bass.fcoRate = 0.0;
bass.fcoAmount = 0.0;

bass.vol = 0.8;
bass.atk = 0.01;
bass.dec = 0.2;
bass.sus = 0.5;
bass.rel = 0.2;

out.playNote(0.0, 1.0, new InstrumentModule(bass));
```

---

## 揺れるフィルター音

```java
InstrumentConfig wobble = new InstrumentConfig();

wobble.out = out;
wobble.waves = new String[] { "SAW" };
wobble.baseFreq = 220.0;
wobble.harmonics = new float[] { 1.0, 0.6, 0.3 };

wobble.cutoff = 3000.0;
wobble.res = 0.5;
wobble.filterMode = 0;

wobble.fcoRate = 5.0;
wobble.fcoAmount = 1500.0;

wobble.vol = 0.6;
wobble.atk = 0.05;
wobble.dec = 0.3;
wobble.sus = 0.4;
wobble.rel = 1.0;

out.playNote(0.0, 2.0, new InstrumentModule(wobble));
```

---

## 軽いハイパス音

```java
InstrumentConfig high = new InstrumentConfig();

high.out = out;
high.waves = new String[] { "TRIANGLE", "SQUARE" };
high.baseFreq = 330.0;
high.harmonics = new float[] { 1.0, 0.3, 0.1 };

high.cutoff = 2000.0;
high.res = 0.3;
high.filterMode = 1;

high.fcoRate = 0.0;
high.fcoAmount = 0.0;

high.vol = 0.5;
high.atk = 0.03;
high.dec = 0.2;
high.sus = 0.4;
high.rel = 0.4;

out.playNote(0.0, 1.0, new InstrumentModule(high));
```

---

# 音作りのコツ

## 丸い音にしたいとき

以下のように設定すると、丸く柔らかい音になりやすいです。

- `"SINE"` や `"TRIANGLE"` を使う
- 倍音を少なめにする
- `cutoff` を低めにする
- `filterMode` を `0` にする

例：

```java
config.waves = new String[] { "SINE", "TRIANGLE" };
config.harmonics = new float[] { 1.0, 0.3 };
```

---

## 明るい音にしたいとき

以下のように設定すると、明るい音になりやすいです。

- `"SAW"` を使う
- 倍音を多めにする
- `cutoff` を高めにする

例：

```java
config.waves = new String[] { "SAW" };
config.harmonics = new float[] { 1.0, 0.7, 0.5, 0.3 };
```

---

## 電子的な音にしたいとき

以下のように設定すると、シンセらしい音になりやすいです。

- `"SQUARE"` や `"SAW"` を使う
- `res` を少し上げる
- FCOを使う

例：

```java
config.waves = new String[] { "SQUARE", "SAW" };
config.fcoRate = 4.0;
config.fcoAmount = 1200.0;
```

---

## 余韻を長くしたいとき

`rel` を大きくします。

```java
config.rel = 1.5;
```

---

## 音の立ち上がりをゆっくりにしたいとき

`atk` を大きくします。

```java
config.atk = 1.0;
```

---

## 音が割れるとき

`vol` を下げてください。

```java
config.vol = 0.4;
```

また、波形や倍音をたくさん重ねると音量が大きくなりやすいです。

その場合は、`harmonics` の値も少し小さくしてください。

```java
config.harmonics = new float[] { 0.7, 0.3, 0.1 };
```

---

# 最小構成の例

```java
import ddf.minim.*;
import ddf.minim.ugens.*;

Minim minim;
AudioOutput out;

void setup() {
  size(400, 400);

  minim = new Minim(this);
  out = minim.getLineOut();
}

void draw() {
  background(0);
}

void keyPressed() {
  if (key == 'p') {
    InstrumentConfig config = new InstrumentConfig();

    config.out = out;
    config.waves = new String[] { "SINE", "TRIANGLE" };
    config.baseFreq = 440.0;
    config.harmonics = new float[] { 1.0, 0.4, 0.2 };

    config.cutoff = 6000.0;
    config.res = 0.1;
    config.filterMode = 0;

    config.fcoRate = 0.0;
    config.fcoAmount = 0.0;

    config.vol = 0.7;
    config.atk = 0.2;
    config.dec = 0.4;
    config.sus = 0.5;
    config.rel = 0.8;

    out.playNote(0.0, 1.0, new InstrumentModule(config));
  }
}
```

---

# パラメータ調整の目安

| 作りたい音 | waves | harmonics | cutoff | filterMode | atk | rel |
|---|---|---|---|---|---|---|
| フルート風 | `"SINE"`, `"TRIANGLE"` | 少なめ | 高め | `0` | 少し長め | 長め |
| ベース風 | `"SQUARE"`, `"SAW"` | 少なめ | 低め | `0` | 短め | 短め |
| シンセリード風 | `"SAW"`, `"SQUARE"` | 多め | 高め | `0` | 短め | 短め |
| 柔らかいパッド風 | `"SINE"`, `"TRIANGLE"` | 中くらい | 中くらい | `0` | 長め | 長め |
| 軽い音 | `"TRIANGLE"` | 少なめ | 中くらい | `1` | 短め | 中くらい |

---

# 使用時の注意

## InstrumentConfigには必要な値を入れる

現在の `InstrumentConfig` には初期値が設定されていません。

そのため、使うときは必要な値を毎回入れてください。

特に以下は忘れないようにしてください。

```java
config.out = out;
config.waves = new String[] { "SINE" };
config.baseFreq = 440.0;
config.harmonics = new float[] { 1.0 };
config.cutoff = 6000.0;
config.vol = 0.7;
```

---

## メロディはInstrumentModuleの外側で管理する

`InstrumentModule` は、1つの音を鳴らすためのクラスです。

メロディを鳴らしたい場合は、`InstrumentModule` の中にメロディ配列を入れるのではなく、外側で `playMelody()` のような関数を作って、音ごとに `baseFreq` を変えて鳴らします。

---

# まとめ

`InstrumentModule` では、以下の流れで音が作られます。

```text
複数のOscil
    ↓
Summer
    ↓
MoogFilter
    ↓
ADSR
    ↓
_out
```

音色を作るときは、まず `InstrumentConfig` に設定を書きます。

```java
InstrumentConfig config = new InstrumentConfig();
```

その設定を `InstrumentModule` に渡して鳴らします。

```java
out.playNote(0.0, 1.0, new InstrumentModule(config));
```

メロディを鳴らすときは、同じ音色設定を使いながら、音ごとに `baseFreq` だけを変えて鳴らします。

音色を大きく変えたいときは、まず以下の値を調整するとわかりやすいです。

- `waves`
- `harmonics`
- `cutoff`
- `filterMode`
- `fcoRate`
- `fcoAmount`
- `atk`
- `rel`

最初は小さめの音量で試し、音が割れないように調整してください。
