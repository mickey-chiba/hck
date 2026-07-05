# ジッタ計測用のテストスクリプト: カラーセンサ側 (ketugou/process/rgb/rgb.pde) の代わりに
# 固定BPMをUDPでArduinoへ送り続ける。
#
# 使い方:
#   python send_test_bpm.py                     # BPM 120 をデフォルト宛先へ送信
#   python send_test_bpm.py --bpm 90            # BPMを変更
#   python send_test_bpm.py --broadcast 172.20.10.15  # 宛先を変更(iPhoneテザリング等)
#
# 宛先のブロードキャストアドレスは「自分のIPの末尾を255にしたもの」。
# Windowsなら ipconfig で「IPv4 アドレス」を確認する(例: 192.168.10.5 → 192.168.10.255)。
#
# 送信仕様は rgb.pde と同一:
#   - BPM: 4バイト リトルエンディアン float → ポート4286
#   - 時刻同期: 80msごとに12バイト(int32の-1 + int64のマイクロ秒時刻)

import argparse
import socket
import struct
import time

PORT = 4286              # Arduino側 (LED_delay_measure.ino) が待ち受けるポート
SYNC_INTERVAL = 0.08     # 時刻同期の送信間隔(80ms)。rgb.pde と同じ値
BPM_INTERVAL = 1.0       # BPMの再送間隔(秒)。Arduinoは同値を無視するので再送しても安全


def main():
    # argparse: コマンドライン引数を解析する標準ライブラリ
    parser = argparse.ArgumentParser(description="固定BPMをUDPブロードキャストで送信するテストスクリプト")
    parser.add_argument("--bpm", type=float, default=120.0, help="送信するBPM(デフォルト: 120)")
    parser.add_argument("--broadcast", default="192.168.10.255",
                        help="宛先アドレス(デフォルト: 192.168.10.255。rgb.pde と同じ)")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    # ブロードキャスト送信を許可するソケットオプション
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

    # struct.pack: 値をバイナリ(バイト列)に変換する。"<" はリトルエンディアン指定
    bpm_packet = struct.pack("<f", args.bpm)

    print(f"BPM {args.bpm} を {args.broadcast}:{PORT} へ送信開始 (Ctrl+C で終了)")

    last_bpm_send = 0.0
    try:
        # 無限ループ: 80msごとに時刻同期、1秒ごとにBPMを送る
        while True:
            now = time.monotonic()  # OS起動からの単調増加時刻(秒)。時計合わせの影響を受けない

            # 時刻同期パケット: int32の-1(マーカー) + int64のマイクロ秒時刻
            # rgb.pde の System.nanoTime()/1000 に相当
            sync_packet = struct.pack("<iq", -1, time.monotonic_ns() // 1000)
            sock.sendto(sync_packet, (args.broadcast, PORT))

            # BPMは1秒ごとに再送(Arduino起動が遅れても届くように)
            if now - last_bpm_send >= BPM_INTERVAL:
                sock.sendto(bpm_packet, (args.broadcast, PORT))
                last_bpm_send = now

            time.sleep(SYNC_INTERVAL)
    except KeyboardInterrupt:
        # Ctrl+C で例外(KeyboardInterrupt)が飛んでくるので、それを捕まえて正常終了する
        print("\n送信を終了しました")
    finally:
        sock.close()


if __name__ == "__main__":  # このファイルを直接実行したときだけ main() を動かすPythonの慣用句
    main()
