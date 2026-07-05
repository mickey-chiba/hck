// LED_delay_measure.pde
// Arduino版 LED_delay_measure.ino の「遅延計測部分」を Processing に移植したスケッチ。
// BPM から次の期待点灯時刻を計算し、実際に点灯処理が走った時刻とのズレ（遅延）を
// コンソールに出力する。LED の代わりに画面中央の円を点滅させる。
//
// Arduino版との対応:
//   - UDPでのBPM受信  -> ↑/↓キーによるBPM変更（applyBpm()）
//   - led1.setBrightness() -> 画面上の円の塗り色切り替え
//   - Serial.print("[遅延] ...") -> println("[遅延] ...")

float currentValue = 60.0; // 現在のBPM（Arduino版ではUDP受信で更新していた値）

// 遅延計測用変数（Arduino版 82〜85行目と同名）
long    receiveTime  = 0;     // BPM設定時刻（ms）
long    expectedTime = 0;     // 次の期待点灯時刻（ms）
boolean ledOn        = false; // LED点灯状態

long lastJitter = 0; // 直近の遅延値（画面表示用）

void setup()
{
    size(400, 400);

    // draw()の呼び出し間隔がそのまま計測分解能になるため、
    // 上限いっぱいまで回るよう高い値を要求する（実際の速度は環境依存）
    frameRate(1000);

    // Arduino版でBPM受信時に行っていた初期化と同じ処理を起動時に実行する
    applyBpm(currentValue);

    println("==================================");
    println(" LED遅延計測プログラム (Processing版) 開始");
    println(" 計測項目:");
    println("   [遅延] 期待点灯時刻 -> 実点灯のズレ（ms）");
    println("==================================");
}

// BPM設定時に受信時刻と次の期待点灯時刻を記録する
// （Arduino版 286〜289行目のUDP受信ブロック内の処理に対応）
void applyBpm(float bpm)
{
    currentValue = bpm;
    receiveTime  = millis(); // millis()はint返しだがlongへ暗黙の拡大変換で代入される
    long interval_ms = (long)(60000.0 / currentValue); // 1拍の長さ（ms）へ型キャスト
    expectedTime = receiveTime + interval_ms;
    println("BPM = " + currentValue);
}

void draw()
{
    background(0);

    // BPMに合わせてLEDを点灯し、今回の遅延（ズレ）だけを計測する
    // （Arduino版 405〜429行目の遅延計測ブロックの移植）
    if (currentValue > 0)
    {
        long interval_ms = (long)(60000.0 / currentValue);
        long now         = millis();

        if (now >= expectedTime)
        {
            long ledTime = millis();
            ledOn = !ledOn; // 論理否定演算子で点灯状態をトグルする

            if (ledOn)
            {
                // 期待点灯時刻と実際の点灯時刻のズレ（今回の遅延のみ）
                long jitter = ledTime - expectedTime;
                lastJitter  = jitter;
                println("[遅延] " + jitter + " ms");
            }

            // ドリフト防止のため実際の時刻ではなく期待値に加算する
            expectedTime += interval_ms;
        }
    }

    // LEDの代わりに円を描画する（三項演算子で点灯時は白、消灯時は暗灰色を選ぶ）
    fill(ledOn ? 255 : 40);
    ellipse(width / 2, height / 2, 150, 150);

    // 現在のBPMと直近の遅延を画面に表示する
    // （デフォルトフォントは日本語を描画できないため表示文字列は英数字のみ）
    fill(255);
    textAlign(CENTER);
    text("BPM: " + nf(currentValue, 0, 1), width / 2, height - 60);
    text("delay: " + lastJitter + " ms", width / 2, height - 40);
    text("UP/DOWN key: change BPM", width / 2, height - 20);
}

// ↑/↓キーでBPMを変更する（Arduino版のUDPによるBPM受信の代替入力）
void keyPressed()
{
    // keyCodeはProcessing組み込みのグローバル変数（特殊キーの判定に使う）
    if (keyCode == UP)
    {
        applyBpm(currentValue + 5);
    }
    else if (keyCode == DOWN)
    {
        applyBpm(max(5, currentValue - 5)); // BPMが0以下にならないよう下限を設ける
    }
}
