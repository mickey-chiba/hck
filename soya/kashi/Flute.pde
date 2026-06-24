import ddf.minim.*;
import ddf.minim.ugens.*;
//-------s
import ddf.minim.analysis.*;
//-------f
import processing.serial.*;

AudioOutput out;
Minim minim;
InstrumentModule flute;


//-------s
long sendBytes = 0;
FFT fft;

// ===== 日本語フォント =====
PFont font;

Serial myPort;

final int FFT_SIZE = 128;
int numBands = 16;
float[] bandValues = new float[numBands];

int graphX = 60, graphY = 650, graphWidth = 1680, graphHeight = 250;

float minDB = 0;
float maxDB = 80;

int btnX = 20, btnY = 50, btnW = 100, btnH = 40;

String[] lyrics = {"きらきら ひかる", "おそらの ほしよ"};
//String[] lyrics = {"きらきら ひかる", "おそらの ほしよ", "まばたき しては",
//                   "みんなを みてる", "きらきら ひかる", "おそらの ほしよ"};

int currentLyricIndex = 0;
float songStartTime = -1;  // 曲の再生開始時刻（millis）
float songTotalDuration;    // 曲の総再生時間（秒）
boolean songPlaying = false;
float lyricProgress = 0;


final int STAR_NUM = 50;

float[] starX = new float[STAR_NUM];
float[] starY = new float[STAR_NUM];
float[] starSpeed = new float[STAR_NUM];
float[] starSize = new float[STAR_NUM];
//-------f
//-------s---------音程バー
int pitchBarX = 60;
int pitchBarY = 370;
int pitchBarWidth = 1680;
int pitchBarHeight = 240;
//-------f---------

// 各音の高さ
String [] melody = {
  "C5", "C5", "G5", "G5", "A5", "A5", "G5","F5", "F5", "E5", "E5", "D5", "D5", "C5"
};

// 各音の長さ（拍）
float [] duration = {
  0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 1.0f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 1.0f
};

// 各音の開始位置
float [] startTime = {
  0.0f, 0.5f, 1.0f, 1.5f, 2.0f, 2.5f, 3.0f, 4.0f, 4.5f, 5.0f, 5.5f, 6.0f, 6.5f, 7.0f
};

// 各音の音量
float[] amplitudes = {
  1.0f, 0.9f, 1.0f, 0.9f, 1.0f, 0.9f, 1.0f, 1.0f, 0.9f, 1.0f, 0.9f, 1.0f, 0.9f, 1.0f
};

void setup(){
  //-------s
  size(1800, 1000);
  
  frameRate(60);

  // ===== 日本語フォント設定 =====
  //font = createFont("Hiragino Sans", 32, true);
  //font = createFont("NanumPen", 32, true);
  //font = createFont("TsukuARdGothic-Bold", 40, true);
  font = createFont("YuMin-Medium", 40, true);
  textFont(font);
  
  for (int i = 0; i < STAR_NUM; i++) {
  starX[i] = random(20, width - 20);
  starY[i] = random(250, 330);

  starSpeed[i] = random(0.3, 1.0);
  starSize[i] = random(2, 6);
  }
  //-------f

  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 1024);
  pixelDensity(1);

  //-------s
  // FFT初期化
  fft = new FFT(out.bufferSize(), out.sampleRate());

  // 曲の総再生時間を計算（最後の音の開始時間 + その長さ）
  songTotalDuration = startTime[startTime.length - 1] + duration[duration.length - 1];

  // Arduinoとのシリアル通信設定
  println(Serial.list());
  myPort = new Serial(this, Serial.list()[1], 115200);
  //-------f

  //指揮者用Arduinoとのシリアル通信設定
  //port = new Serial(this, "/dev/cu.usbmodemXXXXX", xxxx);

  // //フルートの音色
  // //倍音の数とそれぞれの音量を0.0-1.0の間で設定
  // float[] fluteHarmonics = {1.0, 0.4, 0.1}; 
  // out.playNote(0.0, 1.0, new InstrumentModule(
  //   "波形", 周波数, 倍音配列, カットオフ周波数, レゾナンス,  
  //   音量, atk, dec, sus, rel                  
  // ));

  //トランペットの音色
  //trumpet[] trumpetHarmonics = {1.0, 0.4, 0.1}; 
  // out.playNote(0.0, 1.0, new InstrumentModule(
  //   "波形", 周波数, 倍音配列, カットオフ周波数, レゾナンス,  
  //   音量, atk, dec, sus, rel                  
  // ));
  
  ////--------------s(使えるフォントを検索しました)
  //String[] fonts = PFont.list();

  //for (int i = 0; i < fonts.length; i++) {
  //  println(fonts[i]);
  //}
  ////--------------f
}

void draw(){
  background(20);

  //-------s
  // FFT解析
  long startFFT = System.nanoTime();

  fft.forward(out.left);
  
  long endFFT = System.nanoTime();
  
  float fftTime =
    (endFFT - startFFT) / 1000000.0;
  
  println("FFT = " + fftTime + " ms");

  // スペクトラムデータ更新
  updateSpectrum();

  // ArduinoへFFTデータ送信
  sendFFTToArduino();
  //-------f

  // 波形描画
  drawWaveform();

  //-------s
  // 歌詞インデックス更新
  updateLyricIndex();
  
  // 歌詞表示
  drawLyrics();

  //-------s---------音程バー
  drawPitchBar();
  //-------f---------

  // FFTスペクトラム描画
  drawVerticalAxis();
  drawSpectrum();
  drawFrequencyLabels();
  //-------f

  fill(255);
  textSize(14);

  text("Waveform (Time Domain)", 20, 35);
  //-------s
  text("FFT Spectrum", 20, graphY - 20);
  
  fill(255,255,180);
  textSize(30);
  textAlign(CENTER);
  text("♫ きらきら星", width/2, 80);
  //-------f
  
  //-------s....ここで何fps出てるのか確認する
  fill(255);
  textSize(20);
  text("FPS: " + nf(frameRate, 0, 1), 1600, 40);
  //-------f
  
  //-------s
  fill(255);

  text("TX Bytes: " + sendBytes,
       1500,100);
  
  float throughput =
    (float)sendBytes /
    ((millis()+1)/1000.0);
  
  text("TX Rate: "
       + nf(throughput,0,1)
       + " B/s",
       1500,130);
  //-------f
}

//-------s
void updateSpectrum() {
  for (int i = 0; i < numBands; i++) {
    int index = int(map(i, 0, numBands, 0, fft.specSize()));
    float value = fft.getBand(index);
    bandValues[i] = 20 * log(value + 1);
    bandValues[i] = constrain(bandValues[i], minDB, maxDB);
  }
}

void sendFFTToArduino() {
  for (int i = 0; i < numBands; i++) {
    int val = (int)map(bandValues[i], minDB, maxDB, 0, 255);
    val = constrain(val, 0, 255);
    myPort.write(val);
    sendBytes++;
  }
}
//-------f

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

//-------s
void drawLyrics() {

  // 背景
  fill(30, 30, 50);
  noStroke();
  rect(20, 250, width - 40, 80, 10);

  // 星
  drawStars();

  // 歌詞
  //fill(255, 255, 100);
  //textSize(32);
  //textAlign(CENTER, CENTER);
  //text(lyrics[currentLyricIndex], width / 2, 290);
  drawKaraokeText(
    lyrics[currentLyricIndex],
    lyricProgress
  );

  // タイトル
  textAlign(LEFT, BASELINE);
  fill(200);
  textSize(12);
  text("Lyrics Display", 30, 248);
}

//void updateLyricIndex() {
//  if (songStartTime < 0) return;

//  if (songPlaying) {
//    float elapsed = (millis() - songStartTime) / 1000.0;
//    float progress = elapsed / songTotalDuration;

//    int idx = (int)(progress * lyrics.length);
//    currentLyricIndex = constrain(idx, 0, lyrics.length - 1);

//    if (elapsed > songTotalDuration) {
//      songPlaying = false;

//      // 最後の歌詞を表示したままにする
//      currentLyricIndex = lyrics.length - 1;
//    }
//  }
//}

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
      starY[i] = random(250, 330);
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

  float y = 290;

  // 白文字
  fill(255);
  text(lyric, width/2, y);

  // 黄色部分
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
//-------f

//-------s---------音程バー
void drawPitchBar() {
  // 背景
  fill(15, 15, 30, 220);
  noStroke();
  rect(pitchBarX, pitchBarY, pitchBarWidth, pitchBarHeight, 5);

  // タイトル
  fill(200);
  textSize(12);
  textAlign(LEFT, BASELINE);
  text("Pitch Bar", pitchBarX, pitchBarY - 5);

  // 音程の範囲を計算
  int minNote = noteNameToMidi("C5");
  int maxNote = noteNameToMidi("A5");
  int noteRange = maxNote - minNote;

  float noteBarH = pitchBarHeight / (float)(noteRange + 3);

  // 経過時間を取得
  float elapsed = -1;
  if (songStartTime >= 0 && songPlaying) {
    elapsed = (millis() - songStartTime) / 1000.0;
  } else if (songStartTime >= 0 && !songPlaying) {
    elapsed = songTotalDuration;
  }

  // 音名グリッド線（左端ラベル）
  String[] noteLabels = {"C5", "D5", "E5", "F5", "G5", "A5"};
  for (int n = 0; n < noteLabels.length; n++) {
    int nv = noteNameToMidi(noteLabels[n]);
    float y = pitchBarY + pitchBarHeight
              - map(nv - minNote, -1, noteRange + 1, 0, pitchBarHeight);

    fill(80);
    textSize(10);
    textAlign(RIGHT, CENTER);
    text(noteLabels[n], pitchBarX - 5, y);

    stroke(40, 40, 70);
    line(pitchBarX, y, pitchBarX + pitchBarWidth, y);
  }

  // 各音符バーを描画
  for (int i = 0; i < melody.length; i++) {
    int noteVal = noteNameToMidi(melody[i]);

    float x = pitchBarX
              + map(startTime[i], 0, songTotalDuration, 0, pitchBarWidth);
    float w = map(duration[i], 0, songTotalDuration, 0, pitchBarWidth) - 4;
    float y = pitchBarY + pitchBarHeight
              - map(noteVal - minNote, -1, noteRange + 1, 0, pitchBarHeight)
              - noteBarH / 2;

    // 音程に応じた色（低音=青, 中音=緑, 高音=オレンジ）
    float t = map(noteVal, minNote, maxNote, 0, 1);
    color brightColor;
    if (t < 0.5) {
      brightColor = lerpColor(
        color(80, 160, 255), color(80, 230, 160), t * 2
      );
    } else {
      brightColor = lerpColor(
        color(80, 230, 160), color(255, 180, 60), (t - 0.5) * 2
      );
    }
    color dimColor = lerpColor(brightColor, color(30, 30, 50), 0.7);

    if (elapsed >= 0 && elapsed >= startTime[i]) {
      // 通過中 or 通過済み
      float noteProgress = constrain(
        (elapsed - startTime[i]) / duration[i], 0, 1
      );

      // 色付き部分（通過済み）
      fill(brightColor);
      noStroke();
      rect(x, y, w * noteProgress, noteBarH, 3);

      // 暗い部分（未通過）
      if (noteProgress < 1) {
        fill(dimColor);
        rect(x + w * noteProgress, y,
             w * (1 - noteProgress), noteBarH, 3);
      }
    } else {
      // まだ到達していない
      fill(dimColor);
      noStroke();
      rect(x, y, w, noteBarH, 3);
    }

    // 枠線
    stroke(100, 100, 160, 80);
    noFill();
    rect(x, y, w, noteBarH, 3);
  }

  // 判定バー（赤い縦線）
  if (elapsed >= 0 && elapsed <= songTotalDuration) {
    float lineX = pitchBarX
                  + map(elapsed, 0, songTotalDuration,
                        0, pitchBarWidth);

    // グロー効果
    stroke(255, 60, 60, 60);
    strokeWeight(6);
    line(lineX, pitchBarY, lineX, pitchBarY + pitchBarHeight);

    // メインライン
    stroke(255, 80, 80);
    strokeWeight(2);
    line(lineX, pitchBarY, lineX, pitchBarY + pitchBarHeight);
    strokeWeight(1);

    // 三角マーカー（上部）
    fill(255, 80, 80);
    noStroke();
    triangle(lineX - 6, pitchBarY,
             lineX + 6, pitchBarY,
             lineX, pitchBarY + 10);
  }
}

int noteNameToMidi(String name) {
  char note = name.charAt(0);
  int octave = name.charAt(name.length() - 1) - '0';
  boolean sharp = name.indexOf('#') >= 0;

  int semitone = 0;
  switch (note) {
    case 'C': semitone = 0;  break;
    case 'D': semitone = 2;  break;
    case 'E': semitone = 4;  break;
    case 'F': semitone = 5;  break;
    case 'G': semitone = 7;  break;
    case 'A': semitone = 9;  break;
    case 'B': semitone = 11; break;
  }
  if (sharp) semitone++;

  return (octave + 1) * 12 + semitone;
}
//-------f---------

void playSong() {
  out.pauseNotes();

  //-------s
  songStartTime = millis();
  songPlaying = true;
  currentLyricIndex = 0;
  //-------f

  for (int i = 0; i < melody.length; i++) {
    InstrumentConfig flute = new InstrumentConfig();

    flute.out = out;
    flute.waves = new String[] { "SINE", "SINE", "SINE", "SINE", "SINE" };

    // melody[i] の音階名を周波数に変換して、この音の基音にする
    flute.baseFreq = Frequency.ofPitch(melody[i]).asHz();
    // flute.baseFreq = Frequency.ofPitch(pitch).asHz();

    flute.harmonics = new float[] { 1.0, 0.3, 0.05, 0.01, 0.002 };
    flute.cutoff = 1000.0;
    flute.res = 0.0;
    flute.filterMode = 0;
    flute.fcoRate = 0.1;
    flute.fcoAmount = 500.0;

    // amplitudes[i] を使って、音ごとの強弱を変える
    flute.vol = amplitudes[i];

    //flute.noiseVol = amplitudes[i] * 0.05;

    flute.atk = 0.05;
    flute.dec = 0.5;
    flute.sus = 0.7;
    flute.rel = 0.3;

    out.playNote(
      startTime[i],
      duration[i] * 0.9,
      new InstrumentModule(flute)
    );
  }
  out.resumeNotes();
}

void keyPressed() {
  switch (key) {
    case 'a':
      playSong();
      break;

    // case 's':
    //   playSong("D5");
    //   break;

    // case 'd':
    //   playSong("E5");
    //   break;

    // case 'f':
    //   playSong("F5");
    //   break;

    // case 'g':
    //   playSong("G5");
    //   break;

    // case 'h':
    //   playSong("A5");
    //   break;

    // case 'j':
    //   playSong("B5");
    //   break;

    // case 'k':
    //   playSong("C6");
    //   break;
  }
}
