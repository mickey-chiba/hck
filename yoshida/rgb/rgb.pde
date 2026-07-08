import processing.serial.*;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;

DatagramSocket udpSocket;

String broadcastIP = "192.168.11.255";
int port = 4286;
long lastSync = 0;  

Serial myPort;
color myColor = color(255);
long colorChangeTime = 0;  


float baseBPM      = 40.0;
float currentBPM   = 60.0;
float[] multipliers = { 1.0, 1.325, 1.65, 1.975, 2.3, 2.625 };

// 実測値に更新
float[] targetHues  = { 0.006, 0.032, 0.084, 0.22, 0.662, 0.01 };

// ホワイトバランス補正係数を追加
float WB_R = 1.0;
float WB_G = 1.4;
float WB_B = 2.429;

// 継続性確認フィルタ用変数
int   lastBestIndex      = -1;
int   consecutiveCount   = 0;
final int N              = 1;

void setup() {
  size(400, 150);
  background(255);
  noStroke();
  println(Serial.list());
  myPort = new Serial(this, "/dev/tty.usbmodem34B7DA643C542", 115200);
  myPort.bufferUntil('\n');
  delay(3000);
  myPort.write('A');
  colorChangeTime = millis(); 
  try {
  udpSocket = new DatagramSocket();
  }
  catch(Exception e) {
  e.printStackTrace();
  }

}

void draw() {
  if (millis() - lastSync > 80) {    
    sendSync();
    lastSync = millis();
  }
  colorMode(RGB, 255);
  background(0);  
  fill(255, 0, 0);  
  textSize(50);
  text("BPM: " + currentBPM, 20, 100);
}

void sendFloat(float value) {

  try {

    ByteBuffer buffer = ByteBuffer.allocate(4);

    buffer.order(ByteOrder.LITTLE_ENDIAN);
    buffer.putFloat(value);

    byte[] data = buffer.array();

    InetAddress address = InetAddress.getByName(broadcastIP);

    DatagramPacket packet =
      new DatagramPacket(data, data.length, address, port);

    udpSocket.send(packet);

  }
  catch(Exception e) {
    e.printStackTrace();
  }
}
void sendSync() {      //基準時刻を送信する処理

  try {

    ByteBuffer bb = ByteBuffer.allocate(12);

    bb.order(ByteOrder.LITTLE_ENDIAN);

    bb.putInt(-1);

    long pcTime = System.nanoTime() / 1000L;

    bb.putLong(pcTime);

    DatagramPacket p = new DatagramPacket(bb.array(), 12,
                       InetAddress.getByName(broadcastIP),
                       port);
    udpSocket.send(p);
  }
  catch(Exception e) {
    e.printStackTrace();
  }
}

void serialEvent(Serial myPort) {
  long start = millis();

  String received = myPort.readStringUntil('\n');

  if (received != null) {
    received = trim(received);
    if (received.length() == 0) {  
    return;
    }

    int sensorColor[] = int(split(received, ','));

    if (sensorColor.length == 3) {
      int red   = sensorColor[0];
      int green = sensorColor[1];
      int blue  = sensorColor[2];

      float rLin = pow(red   / 255.0, 2.2);
      float gLin = pow(green / 255.0, 2.2);
      float bLin = pow(blue  / 255.0, 2.2);

      // ホワイトバランス補正
      rLin = min(rLin * WB_R, 1.0);
      gLin = min(gLin * WB_G, 1.0);
      bLin = min(bLin * WB_B, 1.0);

      float h = calcHue(rLin, gLin, bLin);

      float minError  = 1.0;
      int   bestIndex = 0;
      for (int i = 0; i < targetHues.length; i++) {
        float error = sq(h - targetHues[i]);
        if (error < minError) {
          minError  = error;
          bestIndex = i;
        }
      }


      // 赤・橙をR/G比で判定
      if (bestIndex == 0 || bestIndex == 1) {
      float rgRatio = (float)red / green;
      if (rgRatio > 3.0) {
       bestIndex = 0;  // 赤
      } else {
      bestIndex = 1;  // 橙
      }
      }

      // 橙・紫をB/G比で判定
      if (bestIndex == 1 || bestIndex == 5) {
      float bgRatio = (float)blue / green;
      if (bgRatio > 0.60) {
      bestIndex = 5;  // 紫
      } else {
      bestIndex = 1;  // 橙
      }
      }
      
      if (bestIndex == 0 || bestIndex == 5) {

      float rgRatio = (float)red  / (green + 1);
      float bgRatio = (float)blue / (green + 1);

      if (rgRatio > 2.5 && bgRatio < 0.70) {
      bestIndex = 0;  // 赤
      } else {
      bestIndex = 5;  // 紫
      }
      }  
      
      if (blue > 60 && red < 120) {
      bestIndex = 4;
      }
      

      // 継続性確認フィルタ部分を修正
      if (bestIndex == lastBestIndex) {
      consecutiveCount++;
      } else {
      consecutiveCount = 1;
      lastBestIndex = bestIndex;
      colorChangeTime = millis();  // 色が変わった瞬間を記録
      }  

      if (consecutiveCount >= N) {
        currentBPM = baseBPM * multipliers[bestIndex];
        
        sendFloat(currentBPM);
        
        consecutiveCount = 0;
        long elapsed = millis() - colorChangeTime;  // 色変化からBPM更新までの時間
        println("BPM更新: " + currentBPM + "  応答時間: " + elapsed + "ms");
        colorChangeTime = millis(); 
        }


      colorMode(RGB, 255);
      myColor = color(red, green, blue);
      colorMode(HSB, 1.0);
      myColor = color(hue(myColor), saturation(myColor) * 1.5, brightness(myColor) * 1.5);
    }
    myPort.write('A');
  }
}

float calcHue(float r, float g, float b) {
  float maxC  = max(r, max(g, b));
  float minC  = min(r, min(g, b));
  float delta = maxC - minC;
  if (delta < 0.0001) return 0.0;
  float h = 0.0;
  if (maxC == r) {
    h = (g - b) / delta;
  } else if (maxC == g) {
    h = 2.0 + (b - r) / delta;
  } else {
    h = 4.0 + (r - g) / delta;
  }
  h /= 6.0;
  if (h < 0.0) h += 1.0;
  return h;
}
