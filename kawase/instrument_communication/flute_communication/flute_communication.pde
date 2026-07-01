import ddf.minim.*;
import ddf.minim.ugens.*;
import processing.serial.*;
import java.nio.*;

Serial myPort;
float tempo = 0.0;
int N;
float updatedtempo = 0.0;
AudioOutput out;
Minim minim;
InstrumentModule flute;

String[] melody;

float[] duration;
float[] startTime;
float[] amplitudes;

boolean dataLoaded = false; 
// テンポ管理 
float   currentBPM = 0;

// musicalTime管理 
boolean   playing     = false;
float     musicalTime = 0;
long      lastTimeMs  = 0;
boolean[] noteStarted;

NoteJob[] activeNotes;           // 音を管理する配列
class NoteJob {
  InstrumentModule inst;         // 音符を担当するinstrument
  boolean        done;           

  NoteJob(InstrumentModule i) {
    inst = i; done = false;
  }

  void stop() {                                //音符を止めるメソッド
    if (!done) {
      inst.noteOff(); // InstrumentModuleのnoteOff()を呼ぶ
      done = true;
    }
  }
}

void setup(){
  size(600, 400);
  myPort = new Serial(this, "", 115200);    //シリアル通信の設定(""にはArduinoのポート番号を入力)
  minim = new Minim(this);
  out = minim.getLineOut();
  myPort.write(0xDD);
  println("start!");
  myPort.clear();
}

void draw() {
  checkdata();
  background(0);
  stroke(255);
  for(int i = 0; i < out.bufferSize() - 1; i++)        //波形の表示処理
  {
    line( i, 50 + out.left.get(i)*50, i+1, 50 + out.left.get(i+1)*50 );
  }

}



void checkdata() {                //データの処理を行う関数
  if (myPort.available() < 1) return;   
  int b1 = myPort.read();
  if(b1 == 0xAA){
    if (!waitForData(1)) return;
    int b2 = myPort.read();
    if (b2 == 0x55)  {
      if(!dataLoaded) {
        readData();
      }
    }
  }else if (b1 == 0xBB) {
      if (!waitForData(1)) return;
      int b2 = myPort.read();
      if (b2 == 0x66) {
        if (!waitForData(4)) return;
        readbpm();
      }
    
  }else if (b1 == 0xCC) {
    // 発音ヘッダー
    if (!waitForData(1)) return;
    if (myPort.read() != 0x33) return;
    readNoteEvent();
    
  }
  
}

void readbpm() {
  if(myPort.available() >= 4){     //4バイト以上だったら処理開始
    byte[] buf = myPort.readBytes(4);
  
    if (buf != null && buf.length == 4) {
    
      ByteBuffer bb = ByteBuffer.wrap(buf);
      bb.order(ByteOrder.LITTLE_ENDIAN);
      tempo = bb.getFloat();
      println("現在のBPM:" + tempo);
      }    
  }
 }
void readNoteEvent() {
  if (!waitForData(2)) { myPort.clear(); return; }

  int index  = myPort.read() & 0xFF; // 音符インデックス
  int onOff  = myPort.read() & 0xFF; // 1=ON 0=OFF
  
  //println("NOTE_EVENT受信 index=" + index + " onOff=" + onOff
  //        + " N=" + N + " activeNotes=" + (activeNotes != null));

  //if (activeNotes == null) {
  //  println("配列受信完了前にNOTE_ONが届いた");
  //  return;
  //}
  if (activeNotes == null && N > 0) {
    activeNotes = new NoteJob[N];
    println("readNoteEvent内でactiveNotes初期化 N=" + N);
  }
  if (index < 0 || index >= N) {
    println("index範囲外: " + index + " N=" + N);
    return;
  }

  InstrumentConfig flute = new InstrumentConfig();

    flute.out = out;
    flute.waves = new String[] { "SINE", "SINE", "SINE", "SINE", "SINE" };

    // melody[i] の音階名を周波数に変換して、この音の基音にする
    flute.baseFreq = Frequency.ofPitch(melody[index]).asHz();
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

  

  if (onOff == 1) {
    inst.noteOn(0); // Arduinoがタイミングを管理するため0でOK
    activeNotes[index] = new NoteJob(inst);  //クラスの配列に発音した情報を記録する
    println("NOTE_ON: " + melody[index]);

  } else if (onOff == 0) {
    // NOTE_OFF：対応するNoteJobのstop()を呼ぶ
    if (activeNotes[index] != null) {
      activeNotes[index].stop();      
      activeNotes[index] = null;
      println("NOTE_OFF: " + index);
    }
  }
}  
void readData() {

  if (!waitForData(1)) return;
  N = myPort.read() & 0xFF; 
  if (N <= 0 || N > 100) { 
    println("invalid N:", N);
    N = 0;
    return;
  }
  activeNotes = new NoteJob[N];
//string配列受信
  melody = new String[N];
  for (int i = 0; i < N; i++) {
    if (!waitForData(1)) {
      println("String長さ受信タイムアウト i=" + i);
      return;
    }
    int strLen = myPort.read() & 0xFF;

    if (!waitForData(strLen)) {
      println("String本体受信タイムアウト i=" + i);
      return;
    }
    byte[] strBuf = myPort.readBytes(strLen);
    melody[i] = new String(strBuf, java.nio.charset.StandardCharsets.UTF_8);
  }
  println("melody");
  printArray(melody);
  
  //各配列受信
  int totalBytes = N * 4 * 1;     //要素数 * バイト数 * 配列数
  
  if (!waitForData(totalBytes)) {
    println("配列データの受信タイムアウト");
    println("  → Processingが待っていたバイト数: " + totalBytes + " バイト");
    println("  → 実際にシリアルポートに届いたバイト数: " + myPort.available() + " バイト");
    println("--------------------------------------------------");
    return;
  }  

  byte[] buf = myPort.readBytes(totalBytes);
  ByteBuffer bb = ByteBuffer.wrap(buf);
  bb.order(ByteOrder.LITTLE_ENDIAN);

  amplitudes = new float[N];  
  // 4番目：amplitudes
  for (int i = 0; i < N; i++) {
    amplitudes[i] = bb.getFloat();
  }

  

  println("amplitudes");
  printArray(amplitudes);

  println("受信成功");
  if (activeNotes != null) {
    for (int i = 0; i < activeNotes.length; i++) {
      if (activeNotes[i] != null) {
        activeNotes[i].stop();
        activeNotes[i] = null;
      }
    }
  }
  dataLoaded = true;
  activeNotes = new NoteJob[N];
  myPort.write(0xFF);
  println("READY送信");
  myPort.clear();
}

boolean waitForData(int requiredBytes) {
  int waitStart = millis();
  while (myPort.available() < requiredBytes) {
    if (millis() - waitStart > 20) { 
      return false;
    }
    delay(1); 
  }
  return true;
}

