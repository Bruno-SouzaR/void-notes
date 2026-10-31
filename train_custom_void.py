#!/usr/bin/env python3
import os
import sys
import glob
import wave
import random
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
import openwakeword

class VoidWakeNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(1536, 64)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(64, 1)
        self.sigmoid = nn.Sigmoid()

    def forward(self, x):
        # Flatten [B, 16, 96] -> [B, 1536]
        x = x.reshape(x.size(0), -1)
        x = self.relu(self.fc1(x))
        return self.sigmoid(self.fc2(x))

def load_wav_i16(path, target_len=32000):
    with wave.open(path, 'rb') as w:
        raw = w.readframes(w.getnframes())
        arr = np.frombuffer(raw, dtype=np.int16)
        if len(arr) < target_len:
            return np.pad(arr, (0, target_len - len(arr)), mode='constant')
        return arr[:target_len]

def main():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(base_dir)

    pos_dir = os.path.join(base_dir, "dataset/positive")
    neg_dir = os.path.join(base_dir, "dataset/negative")
    output_onnx = os.path.join(base_dir, "models/void_custom.onnx")

    pos_files = glob.glob(os.path.join(pos_dir, "*.wav"))
    if not pos_files:
        print(f"Erro: Nenhuma amostra encontrada em '{pos_dir}'.")
        print("Execute primeiro './record_samples.py' para gravar suas amostras de 'VOID'.")
        sys.exit(1)

    print("============================================================")
    print("  void-notes — Treinador Local da Rede Neural 'VOID'")
    print("============================================================")
    print(f"  Amostras de voz encontradas: {len(pos_files)}")
    print("  Extraindo embeddings acústicos com openWakeWord...")

    # Load openWakeWord AudioFeatures extractor
    oww_model = openwakeword.Model()

    # Load ambient noise
    ambient_file = os.path.join(neg_dir, "ambient_room.wav")
    ambient_i16 = load_wav_i16(ambient_file, 160000) if os.path.exists(ambient_file) else np.zeros(32000, dtype=np.int16)

    # 1. Augment Positive Samples
    pos_clips = []
    target_len = 32000 # exactly 2.0s = 16 embedding frames

    for path in pos_files:
        base_audio = load_wav_i16(path, target_len).astype(np.float32)

        # Generate 40 augmented variations per sample
        for _ in range(40):
            # Time shift (+/- 80ms = +/- 1280 samples)
            shift = random.randint(-1280, 1280)
            shifted = np.roll(base_audio, shift)

            # Volume scaling (0.75x to 1.35x)
            scale = random.uniform(0.75, 1.35)
            scaled = shifted * scale

            # Add random ambient background noise
            if len(ambient_i16) > target_len:
                start_n = random.randint(0, len(ambient_i16) - target_len)
                noise_slice = ambient_i16[start_n:start_n + target_len].astype(np.float32)
                scaled += noise_slice * random.uniform(0.05, 0.20)

            scaled = np.clip(scaled, -32768.0, 32767.0).astype(np.int16)
            pos_clips.append(scaled)

    pos_clips = np.array(pos_clips, dtype=np.int16)
    print(f"  Calculando embeddings de {len(pos_clips)} amostras positivas aumentadas...")
    pos_embeddings = oww_model.preprocessor.embed_clips(pos_clips, batch_size=64)

    # 2. Extract Negative Samples (Ambient noise + synthetic noise)
    print("  Calculando embeddings para amostras negativas (ruído e silêncio)...")
    neg_clips = []
    if len(ambient_i16) >= target_len:
        step = 8000 # 500ms sliding step
        for start in range(0, len(ambient_i16) - target_len, step):
            neg_clips.append(ambient_i16[start:start + target_len])

    # Add random noise variations
    for _ in range(len(pos_clips) * 2):
        noise = (np.random.normal(0, 300, target_len)).clip(-32768, 32767).astype(np.int16)
        neg_clips.append(noise)
        if len(neg_clips) >= len(pos_clips) * 2:
            break

    neg_clips = np.array(neg_clips, dtype=np.int16)
    neg_embeddings = oww_model.preprocessor.embed_clips(neg_clips, batch_size=64)

    # Verify shapes
    print(f"  Shape dos embeddings positivos: {pos_embeddings.shape}")
    print(f"  Shape dos embeddings negativos: {neg_embeddings.shape}")

    # Build Training Tensors
    X_pos = torch.tensor(pos_embeddings, dtype=torch.float32)
    y_pos = torch.ones(len(X_pos), 1, dtype=torch.float32)

    X_neg = torch.tensor(neg_embeddings, dtype=torch.float32)
    y_neg = torch.zeros(len(X_neg), 1, dtype=torch.float32)

    X = torch.cat([X_pos, X_neg], dim=0)
    y = torch.cat([y_pos, y_neg], dim=0)

    # 3. Train PyTorch Model
    print("\n  Treinando classificador neural VoidWakeNet...")
    model = VoidWakeNet()
    criterion = nn.BCELoss()
    optimizer = optim.Adam(model.parameters(), lr=0.003, weight_decay=1e-4)

    epochs = 50
    batch_size = 32
    indices = np.arange(len(X))

    for epoch in range(1, epochs + 1):
        np.random.shuffle(indices)
        epoch_loss = 0.0
        n_batches = len(indices) // batch_size

        for b in range(n_batches):
            b_idx = indices[b * batch_size:(b + 1) * batch_size]
            b_X = X[b_idx]
            b_y = y[b_idx]

            optimizer.zero_grad()
            preds = model(b_X)
            loss = criterion(preds, b_y)
            loss.backward()
            optimizer.step()
            epoch_loss += loss.item()

        if epoch % 10 == 0 or epoch == epochs:
            avg_loss = epoch_loss / n_batches
            with torch.no_grad():
                preds_all = model(X)
                acc = ((preds_all >= 0.5) == (y == 1.0)).float().mean().item() * 100.0
            print(f"    Epoch {epoch:02d}/{epochs:02d} | Perda: {avg_loss:.4f} | Acurácia: {acc:.1f}%")

    # 4. Export to ONNX
    print(f"\n  Exportando modelo 'VOID' para '{output_onnx}'...")
    model.eval()
    dummy_input = torch.randn(1, 16, 96, dtype=torch.float32)

    torch.onnx.export(
        model,
        dummy_input,
        output_onnx,
        export_params=True,
        opset_version=14,
        do_constant_folding=True,
        input_names=['onnx::Flatten_0'],
        output_names=['13'],
        dynamic_axes={'onnx::Flatten_0': {0: 'batch_size'}, '13': {0: 'batch_size'}}
    )

    file_size_kb = os.path.getsize(output_onnx) / 1024.0
    print(f"  ✓ Modelo 'VOID' personalizado gerado com sucesso! ({file_size_kb:.1f} KB)")
    print("============================================================\n")

if __name__ == "__main__":
    main()
