import ddf.minim.*;
import ddf.minim.ugens.*;
import processing.serial.*;

AudioOutput out;
Minim minim;
InstrumentModule flute;

//--------wav録音処理追加----------
AudioRecorder recorder;       // WAV録音用レコーダー
boolean isRecording = false;  // 録音中かどうか
long recordStartTime = 0;     // 録音開始時刻（ms）
// 曲全体の長さ: startTime最終値 + duration最終値 + relの余裕
final float SONG_DURATION_SEC = 8.5;
//-------------------------------

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
  0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f, 0.5f
};

void setup(){
  size(700, 800);
  minim = new Minim(this);
  out = minim.getLineOut(Minim.STEREO, 1024);
  pixelDensity(1);
  // スケッチフォルダ直下に flute_output.wav として保存する
  recorder = minim.createRecorder(out, "flute_output.wav");
}
void draw(){
  background(0);
  stroke(255);

  // 左チャンネルと右チャンネルに入っている波形を描画
  for(int i = 0; i < out.bufferSize() - 1; i++)
  {
    line( i, 50 + out.left.get(i)*50, i+1, 50 + out.left.get(i+1)*50 );
    line( i, 150 + out.right.get(i)*50, i+1, 150 + out.right.get(i+1)*50 );
  }

//--------wav録音処理追加----------
  // 録音中で曲の長さを超えたら自動停止してファイル保存
  if (isRecording && millis() - recordStartTime > SONG_DURATION_SEC * 1000) {
    recorder.endRecord();
    recorder.save();
    isRecording = false;
    println("録音完了: flute_output.wav");
  }
//-------------------------------
}

void playSong() {
  out.pauseNotes();

  for (int i = 0; i < melody.length; i++) {
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

    out.playNote(
      startTime[i],
      duration[i] * 0.95,
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

//--------wav録音処理追加----------
    // 'r' キーで録音しながら演奏開始（曲が終わると自動保存）
    case 'r':
      recorder.beginRecord();
      isRecording = true;
      recordStartTime = millis();
      playSong();
      println("録音開始...");
      break;
//-------------------------------
  }
}
