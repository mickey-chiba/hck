"""
compute_double_bass_mfcc.py
---------------------
複数のフルートMP3音源からMFCCを計算し、
「フルートらしいMFCC平均ベクトル」をJSONとして出力する。

処理フロー:
  MP3 → WAV(ffmpeg) → ハミング窓 → DFT → メルフィルタ → log → DCT → MFCC
  → 各ファイルの平均MFCC → 全ファイルの grand mean → JSON保存

依存: Python標準ライブラリ + numpy + scipy (追加インストール不要)
"""

import os, json, wave, struct, subprocess, tempfile, math
import numpy as np
from scipy.fft import dct

# ── パラメータ（MFCCAnalyzer.pde と合わせる） ──────────────
SAMPLE_RATE  = 44100
N_MFCC       = 13      # 係数数
N_FILTERS    = 26      # メルフィルタ数
FFT_SIZE     = 1024    # FFTサイズ
HOP_SIZE     = 512     # フレームシフト（50%オーバーラップ）
F_MIN        = 80.0    # メルフィルタ最低周波数 [Hz]
F_MAX        = 8000.0  # メルフィルタ最高周波数 [Hz]

# 対象MP3ファイル一覧
MP3_DIR   = "/mnt/user-data/uploads"
MP3_FILES = sorted([
    os.path.join(MP3_DIR, f)
    for f in os.listdir(MP3_DIR)
    if f.startswith("double-bass_") and f.endswith(".mp3")
])

OUTPUT_JSON = "/mnt/user-data/outputs/double_bass_mfcc_reference.json"

# ── ユーティリティ ──────────────────────────────────────────

def hz_to_mel(hz: float) -> float:
    return 2595.0 * math.log10(1.0 + hz / 700.0)

def mel_to_hz(mel: float) -> float:
    return 700.0 * (10.0 ** (mel / 2595.0) - 1.0)

def build_mel_filterbank(n_filters, fft_size, sr, f_min, f_max):
    """
    三角メルフィルタバンク行列を構築する。
    戻り値: shape = (n_filters, fft_size//2 + 1)
    """
    mel_min = hz_to_mel(f_min)
    mel_max = hz_to_mel(f_max)
    # フィルタ中心をメルスケールで等間隔に配置
    mel_points = np.linspace(mel_min, mel_max, n_filters + 2)
    hz_points  = np.array([mel_to_hz(m) for m in mel_points])
    # Hz → FFTビン番号
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

def mp3_to_mono_float(mp3_path: str) -> np.ndarray:
    """ffmpegでMP3→WAV変換してfloat32配列で返す"""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wav_path = f.name
    subprocess.run(
        ["ffmpeg", "-y", "-i", mp3_path,
         "-ar", str(SAMPLE_RATE), "-ac", "1", wav_path],
        capture_output=True, check=True
    )
    with wave.open(wav_path) as wf:
        raw = wf.readframes(wf.getnframes())
        sampwidth = wf.getsampwidth()
    os.unlink(wav_path)

    # 16bit PCM → float32
    samples = np.array(struct.unpack(f"<{len(raw)//sampwidth}h", raw), dtype=np.float32)
    samples /= 32768.0
    return samples

def compute_mfcc_frames(signal: np.ndarray, mel_filters: np.ndarray) -> np.ndarray:
    """
    信号全体をフレーム分割してMFCC行列を返す。
    戻り値: shape = (n_frames, N_MFCC)
    """
    n_frames = max(1, (len(signal) - FFT_SIZE) // HOP_SIZE + 1)
    mfcc_matrix = []

    for i in range(n_frames):
        start = i * HOP_SIZE
        frame = signal[start: start + FFT_SIZE]
        if len(frame) < FFT_SIZE:
            frame = np.pad(frame, (0, FFT_SIZE - len(frame)))

        # (1) ハミング窓
        window  = np.hamming(FFT_SIZE)
        windowed = frame * window

        # (2) FFT → パワースペクトル（片側）
        spectrum = np.fft.rfft(windowed)            # shape: FFT_SIZE//2 + 1
        power    = np.real(spectrum) ** 2 + np.imag(spectrum) ** 2

        # (3) メルフィルタバンク適用 → 対数
        mel_energy    = mel_filters @ power          # shape: n_filters
        log_mel_energy = np.log(np.maximum(mel_energy, 1e-10))

        # (4) DCT-II → MFCC
        mfcc = dct(log_mel_energy, type=2, norm='ortho')[:N_MFCC]
        mfcc_matrix.append(mfcc)

    return np.array(mfcc_matrix)   # (n_frames, N_MFCC)

# ── メイン処理 ──────────────────────────────────────────────

def main():
    os.makedirs(os.path.dirname(OUTPUT_JSON), exist_ok=True)

    print(f"対象ファイル数: {len(MP3_FILES)}")
    mel_filters = build_mel_filterbank(N_FILTERS, FFT_SIZE, SAMPLE_RATE, F_MIN, F_MAX)

    all_file_means = []   # 各ファイルの平均MFCCを蓄積
    file_results   = []   # JSON出力用の詳細

    for path in MP3_FILES:
        fname = os.path.basename(path)
        print(f"  処理中: {fname} ... ", end="", flush=True)

        try:
            signal = mp3_to_mono_float(path)
            mfcc_mat = compute_mfcc_frames(signal, mel_filters)   # (n_frames, 13)
            file_mean = mfcc_mat.mean(axis=0)                     # (13,)
            all_file_means.append(file_mean)

            file_results.append({
                "file":      fname,
                "n_frames":  int(mfcc_mat.shape[0]),
                "duration_s": round(len(signal) / SAMPLE_RATE, 3),
                "mfcc_mean": file_mean.tolist()
            })
            print(f"OK ({mfcc_mat.shape[0]} frames)")

        except Exception as e:
            print(f"SKIP ({e})")

    if not all_file_means:
        print("有効なファイルがありません。終了します。")
        return

    # ── grand mean（フルートらしいMFCC） ──
    grand_mean = np.mean(all_file_means, axis=0)   # (13,)
    grand_std  = np.std(all_file_means,  axis=0)   # (13,) ばらつき参考値

    result = {
        "instrument":   "double_bass",
        "n_files":       len(all_file_means),
        "n_mfcc":        N_MFCC,
        "n_filters":     N_FILTERS,
        "fft_size":      FFT_SIZE,
        "hop_size":      HOP_SIZE,
        "sample_rate":   SAMPLE_RATE,
        "f_min":         F_MIN,
        "f_max":         F_MAX,
        "grand_mean":    grand_mean.tolist(),   # ← これが「フルートらしいMFCC」
        "grand_std":     grand_std.tolist(),    # ← ファイル間のばらつき
        "files":         file_results
    }

    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    print(f"\n=== 完了 ===")
    print(f"出力先: {OUTPUT_JSON}")
    print(f"\n【フルートらしいMFCC平均ベクトル (grand_mean)】")
    for i, v in enumerate(grand_mean):
        bar = "█" * int(abs(v) / 10)
        sign = "+" if v >= 0 else "-"
        print(f"  c{i+1:2d}: {sign}{abs(v):6.2f}  {bar}")

if __name__ == "__main__":
    main()