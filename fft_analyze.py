#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
実楽器音 FFT 解析ツール
========================

ActualSounds/ にある実際の楽器の音ファイル（wav）を読み込み，
FFT による振幅スペクトルを求めて可視化・数値出力する。
合成音との比較（instrument_eval.py）に先立つ「実音の素性調べ」に使う。

やること
--------
  1. 音声読込（モノラル化・float 正規化）
  2. 定常（サステイン）区間の抽出  ※アタック/リリースを避ける
  3. 窓掛け FFT → 振幅スペクトル
  4. 基本周波数 f0 と倍音ピークの検出
  5. スペクトル図の表示／PNG 保存・ピーク表の CSV 出力

使い方
------
  # 1ファイルを解析して図を表示
  python3 fft_analyze.py ActualSounds/flute/flute_A4_025_forte_normal.wav

  # 図を PNG 保存し，ピーク一覧を CSV 出力（画面表示なし）
  python3 fft_analyze.py 実音.wav --plot-save spec.png --csv peaks.csv

  # 定常区間ではなく全体を使う / 表示周波数上限を変える
  python3 fft_analyze.py 実音.wav --no-steady --fmax 8000

依存
----
  numpy, scipy, matplotlib（mp3 は未対応 → wav を渡すこと）

  ※ システムの python3 を使う:  /opt/homebrew/var/pyenv/shims/python3
"""

import argparse
import os
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import get_window


# ===========================================================================
# 1. 音声読込
# ===========================================================================
def read_wav(path):
    """wav を読み込み，モノラルの float64 信号として返す。

    Returns
    -------
    signal : np.ndarray  (float64, モノラル, おおむね [-1, 1])
    sr     : int         (サンプリング周波数 [Hz])
    """
    ext = os.path.splitext(path)[1].lower()
    if ext != ".wav":
        # mp3 等は ffmpeg/librosa が必要。この環境では未対応なので明示的に弾く。
        raise ValueError(
            f"未対応の形式です: {ext}（wav を渡してください）。\n"
            "  同名の .wav が存在することが多いので拡張子を .wav に変えて試してください。"
        )

    sr, data = wavfile.read(path)
    data = np.asarray(data)

    # 整数 PCM を [-1, 1] の float へ
    if np.issubdtype(data.dtype, np.integer):
        max_val = float(np.iinfo(data.dtype).max)
        data = data.astype(np.float64) / max_val
    else:
        data = data.astype(np.float64)

    # ステレオ等はモノラルへ
    if data.ndim > 1:
        data = data.mean(axis=1)

    return data, int(sr)


# ===========================================================================
# 2. 定常（サステイン）区間の抽出
#    アタック・リリースを避け，音色が安定した区間だけで FFT を取る。
#    （instrument_eval.py の extract_steady と同じ考え方）
# ===========================================================================
def extract_steady(signal, sr, frame_ms=20.0, energy_ratio=0.5):
    frame_len = max(1, int(sr * frame_ms / 1000.0))
    n_frames = len(signal) // frame_len
    if n_frames < 3:
        return signal

    frames = signal[: n_frames * frame_len].reshape(n_frames, frame_len)
    rms = np.sqrt(np.mean(frames ** 2, axis=1) + 1e-12)

    thr = rms.max() * energy_ratio
    active = rms >= thr

    # 最長の連続アクティブ区間を採用
    best_start, best_len = 0, 0
    cur_start, cur_len = 0, 0
    for i, a in enumerate(active):
        if a:
            if cur_len == 0:
                cur_start = i
            cur_len += 1
            if cur_len > best_len:
                best_start, best_len = cur_start, cur_len
        else:
            cur_len = 0

    if best_len == 0:
        return signal

    s = best_start * frame_len
    e = (best_start + best_len) * frame_len
    return signal[s:e]


# ===========================================================================
# 3. 窓掛け FFT → 振幅スペクトル
# ===========================================================================
def compute_fft(signal, sr, n_fft=None, window="hann"):
    """単一フレーム（区間全体）の振幅スペクトルを返す。

    Returns
    -------
    freqs : np.ndarray  周波数軸 [Hz]
    mag   : np.ndarray  振幅（線形, |X(f)|）
    """
    n = len(signal)
    if n_fft is None:
        # 区間長を覆う 2 の冪（最低 2048）。周波数分解能 = sr/n_fft。
        n_fft = int(2 ** np.ceil(np.log2(max(n, 2048))))

    if n >= n_fft:
        x = signal[:n_fft]
    else:
        x = np.pad(signal, (0, n_fft - n))

    win = get_window(window, n_fft, fftbins=True)
    x = x * win

    spec = np.fft.rfft(x)
    # 窓のコヒーレントゲインで割って振幅をだいたい校正
    mag = np.abs(spec) / (np.sum(win) / 2.0)
    freqs = np.fft.rfftfreq(n_fft, 1.0 / sr)
    return freqs, mag


# ===========================================================================
# 4. 基本周波数 f0 推定（自己相関法）
# ===========================================================================
def estimate_f0(signal, sr, fmin=50.0, fmax=4000.0):
    x = signal - np.mean(signal)
    if np.sqrt(np.mean(x ** 2)) < 1e-9:
        return 0.0

    win = x * np.hanning(len(x))
    corr = np.correlate(win, win, mode="full")
    corr = corr[len(corr) // 2:]

    lag_min = int(sr / fmax)
    lag_max = min(int(sr / fmin), len(corr) - 1)
    if lag_max <= lag_min:
        return 0.0

    search = corr[lag_min:lag_max]
    peak = np.argmax(search) + lag_min

    # 放物線補間
    if 1 <= peak < len(corr) - 1:
        a, b, c = corr[peak - 1], corr[peak], corr[peak + 1]
        denom = (a - 2 * b + c)
        if abs(denom) > 1e-12:
            peak = peak + 0.5 * (a - c) / denom

    return sr / peak if peak > 0 else 0.0


# ===========================================================================
# 周波数 → 音名（最も近い平均律音）
# ===========================================================================
_NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F",
               "F#", "G", "G#", "A", "A#", "B"]


def hz_to_note(f):
    """周波数 [Hz] を最寄りの音名（例: A4）とセントずれに変換。"""
    if f <= 0:
        return "-", 0.0
    midi = 69 + 12 * np.log2(f / 440.0)
    midi_round = int(round(midi))
    cents = (midi - midi_round) * 100.0
    name = _NOTE_NAMES[midi_round % 12]
    octave = midi_round // 12 - 1
    return f"{name}{octave}", cents


# ===========================================================================
# 倍音ピークの検出（f0 の整数倍周辺で極大を拾う）
# ===========================================================================
def find_harmonic_peaks(freqs, mag, f0, n_harmonics=10):
    """各倍音 f_n = n*f0 周辺のピーク（周波数・振幅・dB）を返す。"""
    if f0 <= 0:
        return []
    bin_hz = freqs[1] - freqs[0] if len(freqs) > 1 else 1.0
    ref = mag.max() + 1e-12  # 最大ピークを 0 dB 基準にする
    peaks = []
    for n in range(1, n_harmonics + 1):
        f_target = n * f0
        if f_target > freqs[-1]:
            break
        half = max(f0 / 2.0, bin_hz)
        lo = np.searchsorted(freqs, f_target - half)
        hi = np.searchsorted(freqs, f_target + half)
        lo, hi = max(lo, 0), min(hi, len(mag))
        if hi <= lo:
            continue
        k = lo + int(np.argmax(mag[lo:hi]))
        amp = mag[k]
        peaks.append({
            "n": n,
            "freq": float(freqs[k]),
            "amp": float(amp),
            "rel_db": float(20.0 * np.log10(amp / ref + 1e-12)),
        })
    return peaks


# ===========================================================================
# 出力：ピーク表
# ===========================================================================
def print_peaks(f0, note, cents, peaks):
    print("\n" + "=" * 48)
    print("  FFT 解析結果")
    print("=" * 48)
    if f0 > 0:
        print(f"  基本周波数 f0 : {f0:.2f} Hz")
        print(f"  最寄り音名    : {note}  ({cents:+.1f} cent)")
    else:
        print("  基本周波数 f0 : 推定不可（無音/非調波）")
    print("-" * 48)
    print(f"  {'倍音':<6}{'周波数[Hz]':>12}{'相対[dB]':>12}")
    print("-" * 48)
    for p in peaks:
        print(f"  H{p['n']:<5}{p['freq']:>12.1f}{p['rel_db']:>12.1f}")
    print("=" * 48 + "\n")


def save_csv(path, f0, note, peaks):
    import csv
    with open(path, "w", newline="", encoding="utf-8-sig") as fp:
        w = csv.writer(fp)
        w.writerow(["f0_Hz", "note", "harmonic", "freq_Hz", "amp", "rel_dB"])
        for p in peaks:
            w.writerow([f"{f0:.3f}", note, p["n"],
                        f"{p['freq']:.3f}", f"{p['amp']:.6g}", f"{p['rel_db']:.3f}"])
    print(f"ピーク一覧を保存しました: {path}")


# ===========================================================================
# 出力：スペクトル図
# ===========================================================================
def plot_spectrum(freqs, mag, f0, peaks, fmax=None, title="", save_path=None):
    import matplotlib
    if save_path:
        matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    if fmax is None:
        # 倍音が十分入る範囲を既定にする
        fmax = min(f0 * 12, freqs[-1]) if f0 > 0 else freqs[-1]

    sel = freqs <= fmax
    db = 20.0 * np.log10(mag / (mag.max() + 1e-12) + 1e-12)  # 最大 0 dB 正規化

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(11, 7), sharex=True)

    # 上：線形振幅
    ax1.plot(freqs[sel], mag[sel], lw=0.9, color="C0")
    ax1.set_ylabel("Magnitude (linear)")
    ax1.set_title(title or "FFT spectrum")
    ax1.grid(alpha=0.3)

    # 下：dB
    ax2.plot(freqs[sel], db[sel], lw=0.9, color="C3")
    ax2.set_ylabel("Magnitude [dB]")
    ax2.set_xlabel("Frequency [Hz]")
    ax2.set_ylim(-80, 5)
    ax2.grid(alpha=0.3)

    # 倍音位置に目印
    for p in peaks:
        if p["freq"] <= fmax:
            for ax in (ax1, ax2):
                ax.axvline(p["freq"], color="gray", ls="--", lw=0.6)
            ax1.annotate(f"H{p['n']}", (p["freq"], mag[np.searchsorted(freqs, p["freq"])]),
                         textcoords="offset points", xytext=(2, 2), fontsize=8)

    plt.tight_layout()
    if save_path:
        plt.savefig(save_path, dpi=120)
        print(f"スペクトル図を保存しました: {save_path}")
    else:
        plt.show()


# ===========================================================================
# 解析本体
# ===========================================================================
def analyze(path, use_steady=True, n_harmonics=10):
    signal, sr = read_wav(path)
    seg = extract_steady(signal, sr) if use_steady else signal

    f0 = estimate_f0(seg, sr)
    note, cents = hz_to_note(f0)

    freqs, mag = compute_fft(seg, sr)
    peaks = find_harmonic_peaks(freqs, mag, f0, n_harmonics)

    return {
        "sr": sr,
        "f0": f0, "note": note, "cents": cents,
        "freqs": freqs, "mag": mag, "peaks": peaks,
    }


# ===========================================================================
# エントリポイント
# ===========================================================================
def main():
    parser = argparse.ArgumentParser(
        description="実楽器音を FFT 解析し，スペクトルと倍音ピークを出力する。")
    parser.add_argument("wav", help="解析する実音 wav ファイル")
    parser.add_argument("--harmonics", type=int, default=10, help="検出する倍音数（既定 10）")
    parser.add_argument("--no-steady", action="store_true",
                        help="定常区間抽出をせず信号全体を解析する")
    parser.add_argument("--fmax", type=float, default=None,
                        help="図に表示する周波数上限 [Hz]（既定: f0 の約12倍）")
    parser.add_argument("--csv", default=None, help="ピーク一覧の CSV 出力先")
    parser.add_argument("--plot", action="store_true", help="スペクトル図を画面表示")
    parser.add_argument("--plot-save", default=None, help="スペクトル図の保存先 PNG")
    args = parser.parse_args()

    if not os.path.exists(args.wav):
        print(f"エラー: ファイルが見つかりません: {args.wav}", file=sys.stderr)
        sys.exit(1)

    try:
        res = analyze(args.wav, use_steady=not args.no_steady,
                      n_harmonics=args.harmonics)
    except ValueError as e:
        print(f"エラー: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"\n読込: {args.wav}  (sr={res['sr']} Hz)")
    print_peaks(res["f0"], res["note"], res["cents"], res["peaks"])

    if args.csv:
        save_csv(args.csv, res["f0"], res["note"], res["peaks"])

    # 図はデフォルトで表示。--plot-save 指定時は保存。
    if args.plot or args.plot_save or not args.csv:
        title = f"{os.path.basename(args.wav)}  (f0={res['f0']:.1f}Hz, {res['note']})"
        plot_spectrum(res["freqs"], res["mag"], res["f0"], res["peaks"],
                      fmax=args.fmax, title=title, save_path=args.plot_save)


if __name__ == "__main__":
    main()
