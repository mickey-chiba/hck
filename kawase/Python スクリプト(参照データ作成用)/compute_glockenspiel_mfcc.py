"""
compute_glockenspiel_mfcc.py
----------------------------
グロッケンシュピールWAV音源からMFCCを計算し、
「グロッケンらしいMFCC平均ベクトル」をJSONとして出力する。

WAVファイルなのでffmpeg変換不要。
"""

import os, json, wave, struct, math
import numpy as np
from scipy.fft import dct

# ── パラメータ（他の楽器スクリプトと統一） ──────────────
SAMPLE_RATE = 44100
N_MFCC      = 13
N_FILTERS   = 26
FFT_SIZE    = 1024
HOP_SIZE    = 512
F_MIN       = 80.0
F_MAX       = 8000.0

# 対象WAVファイル一覧（angstromのグロッケンパック）
WAV_FILES = sorted([
    "/mnt/user-data/uploads/11072__angstrom__a2.wav",
    "/mnt/user-data/uploads/11073__angstrom__a2.wav",
    "/mnt/user-data/uploads/11074__angstrom__b2.wav",
    "/mnt/user-data/uploads/11075__angstrom__c1.wav",
    "/mnt/user-data/uploads/11076__angstrom__c2.wav",
    "/mnt/user-data/uploads/11077__angstrom__c1.wav",
    "/mnt/user-data/uploads/11078__angstrom__c2.wav",
    "/mnt/user-data/uploads/11079__angstrom__d1.wav",
    "/mnt/user-data/uploads/11080__angstrom__d2.wav",
    "/mnt/user-data/uploads/11081__angstrom__d1.wav",
    "/mnt/user-data/uploads/11082__angstrom__d2.wav",
    "/mnt/user-data/uploads/11083__angstrom__e1.wav",
    "/mnt/user-data/uploads/11084__angstrom__e2.wav",
    "/mnt/user-data/uploads/11085__angstrom__f1.wav",
    "/mnt/user-data/uploads/11086__angstrom__f1.wav",
    "/mnt/user-data/uploads/11087__angstrom__g1.wav",
    "/mnt/user-data/uploads/11088__angstrom__g1.wav",
])

OUTPUT_JSON = "/mnt/user-data/outputs/glockenspiel_mfcc_reference.json"

# ── ユーティリティ ──────────────────────────────────────────

def hz_to_mel(hz):
    return 2595.0 * math.log10(1.0 + hz / 700.0)

def mel_to_hz(mel):
    return 700.0 * (10.0 ** (mel / 2595.0) - 1.0)

def build_mel_filterbank(n_filters, fft_size, sr, f_min, f_max):
    mel_min = hz_to_mel(f_min)
    mel_max = hz_to_mel(f_max)
    mel_points = np.linspace(mel_min, mel_max, n_filters + 2)
    hz_points  = np.array([mel_to_hz(m) for m in mel_points])
    bin_points = np.round(hz_points * fft_size / sr).astype(int)
    bin_points = np.clip(bin_points, 0, fft_size // 2)

    n_bins  = fft_size // 2 + 1
    filters = np.zeros((n_filters, n_bins))
    for m in range(n_filters):
        left, center, right = bin_points[m], bin_points[m+1], bin_points[m+2]
        if center > left:
            for k in range(left, center):
                filters[m, k] = (k - left) / (center - left)
        if right > center:
            for k in range(center, right + 1):
                filters[m, k] = (right - k) / (right - center)
    return filters

def wav_to_mono_float(wav_path):
    """WAVファイルをfloat32モノラル配列で返す"""
    with wave.open(wav_path) as wf:
        n_channels = wf.getnchannels()
        sampwidth  = wf.getsampwidth()
        framerate  = wf.getframerate()
        raw        = wf.readframes(wf.getnframes())

    samples = np.array(
        struct.unpack(f"<{len(raw)//sampwidth}h", raw),
        dtype=np.float32
    )
    samples /= 32768.0

    # ステレオの場合は左右平均してモノラルに変換
    if n_channels == 2:
        samples = (samples[0::2] + samples[1::2]) / 2.0

    # サンプルレートが異なる場合は簡易リサンプリング
    if framerate != SAMPLE_RATE:
        ratio   = SAMPLE_RATE / framerate
        new_len = int(len(samples) * ratio)
        indices = (np.arange(new_len) / ratio).astype(int)
        indices = np.clip(indices, 0, len(samples) - 1)
        samples = samples[indices]

    return samples

def compute_mfcc_frames(signal, mel_filters):
    n_frames     = max(1, (len(signal) - FFT_SIZE) // HOP_SIZE + 1)
    mfcc_matrix  = []

    for i in range(n_frames):
        start  = i * HOP_SIZE
        frame  = signal[start: start + FFT_SIZE]
        if len(frame) < FFT_SIZE:
            frame = np.pad(frame, (0, FFT_SIZE - len(frame)))

        # (1) ハミング窓
        windowed = frame * np.hamming(FFT_SIZE)

        # (2) FFT → パワースペクトル
        spectrum = np.fft.rfft(windowed)
        power    = np.real(spectrum)**2 + np.imag(spectrum)**2

        # (3) メルフィルタ → 対数
        mel_energy     = mel_filters @ power
        log_mel_energy = np.log(np.maximum(mel_energy, 1e-10))

        # (4) DCT-II → MFCC
        mfcc = dct(log_mel_energy, type=2, norm='ortho')[:N_MFCC]
        mfcc_matrix.append(mfcc)

    return np.array(mfcc_matrix)

# ── メイン処理 ──────────────────────────────────────────────

def main():
    os.makedirs(os.path.dirname(OUTPUT_JSON), exist_ok=True)
    print(f"対象ファイル数: {len(WAV_FILES)}")

    mel_filters    = build_mel_filterbank(N_FILTERS, FFT_SIZE, SAMPLE_RATE, F_MIN, F_MAX)
    all_file_means = []
    file_results   = []

    for path in WAV_FILES:
        fname = os.path.basename(path)
        print(f"  処理中: {fname} ... ", end="", flush=True)

        try:
            signal   = wav_to_mono_float(path)
            mfcc_mat = compute_mfcc_frames(signal, mel_filters)
            file_mean = mfcc_mat.mean(axis=0)
            all_file_means.append(file_mean)

            file_results.append({
                "file":       fname,
                "n_frames":   int(mfcc_mat.shape[0]),
                "duration_s": round(len(signal) / SAMPLE_RATE, 3),
                "mfcc_mean":  file_mean.tolist()
            })
            print(f"OK ({mfcc_mat.shape[0]} frames)")

        except Exception as e:
            print(f"SKIP ({e})")

    if not all_file_means:
        print("有効なファイルがありません。終了します。")
        return

    grand_mean = np.mean(all_file_means, axis=0)
    grand_std  = np.std(all_file_means,  axis=0)

    result = {
        "instrument":  "glockenspiel",
        "n_files":      len(all_file_means),
        "n_mfcc":       N_MFCC,
        "n_filters":    N_FILTERS,
        "fft_size":     FFT_SIZE,
        "hop_size":     HOP_SIZE,
        "sample_rate":  SAMPLE_RATE,
        "f_min":        F_MIN,
        "f_max":        F_MAX,
        "grand_mean":   grand_mean.tolist(),
        "grand_std":    grand_std.tolist(),
        "files":        file_results
    }

    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    print(f"\n=== 完了 ===")
    print(f"出力先: {OUTPUT_JSON}")
    print(f"\n【グロッケンらしいMFCC平均ベクトル (grand_mean)】")
    for i, v in enumerate(grand_mean):
        bar  = "█" * int(abs(v) / 10)
        sign = "+" if v >= 0 else "-"
        print(f"  c{i+1:2d}: {sign}{abs(v):6.2f}  {bar}")

if __name__ == "__main__":
    main()