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

class WakeNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(1536, 128)
        self.relu1 = nn.ReLU()
        self.fc2 = nn.Linear(128, 64)
        self.relu2 = nn.ReLU()
        self.fc3 = nn.Linear(64, 1)

        # Small normal initialization
        nn.init.normal_(self.fc1.weight, std=0.01)
        nn.init.zeros_(self.fc1.bias)
        nn.init.normal_(self.fc2.weight, std=0.02)
        nn.init.zeros_(self.fc2.bias)
        nn.init.normal_(self.fc3.weight, std=0.02)
        nn.init.zeros_(self.fc3.bias)

    def forward(self, x):
        x = x.reshape(x.size(0), -1)
        x = self.relu1(self.fc1(x))
        x = self.relu2(self.fc2(x))
        return self.fc3(x)

class ExportWakeNet(nn.Module):
    def __init__(self, net):
        super().__init__()
        self.net = net
        self.sigmoid = nn.Sigmoid()

    def forward(self, x):
        return self.sigmoid(self.net(x))

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

    pos_files = sorted(glob.glob(os.path.join(pos_dir, "*.wav")))
    if not pos_files:
        print(f"Erro: Nenhuma amostra encontrada em '{pos_dir}'.")
        print("Execute primeiro './record_samples.py' para gravar suas amostras de 'VOID'.")
        sys.exit(1)

    print("============================================================")
    print("  void-notes — Treinador Local da Rede Neural 'VOID'")
    print("============================================================")
    print(f"  Amostras de voz encontradas: {len(pos_files)}")
    print("  Extraindo embeddings acústicos com openWakeWord...")

    oww_model = openwakeword.Model()

    # 1. Augment Positive Samples (Time shifts & volume scale)
    pos_clips = []
    target_len = 32000 # 2.0s

    for path in pos_files:
        base_audio = load_wav_i16(path, target_len).astype(np.float32)
        for shift in [-800, -400, 0, 400, 800]: # 5 shifts
            shifted = np.roll(base_audio, shift)
            for scale in [0.85, 1.0, 1.15]: # 3 volume levels
                scaled = (shifted * scale).clip(-32768, 32767).astype(np.int16)
                pos_clips.append(scaled)

    pos_clips = np.array(pos_clips, dtype=np.int16)
    print(f"  Calculando embeddings de {len(pos_clips)} amostras positivas aumentadas...")
    pos_embeddings = oww_model.preprocessor.embed_clips(pos_clips, batch_size=128)

    # 2. Extract Negative Samples (Real ambient room noise + Speech from samples)
    print("  Calculando embeddings para amostras negativas (ruído e fala ambiente)...")
    neg_clips = []

    ambient_file = os.path.join(neg_dir, "ambient_room.wav")
    if os.path.exists(ambient_file):
        with wave.open(ambient_file, 'rb') as w:
            amb = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
            for start in range(0, len(amb) - target_len, 2000): # dense slices
                neg_clips.append(amb[start:start + target_len])

    # Speech samples (non-void human speech)
    for sample_wav in ["/tmp/whisper_repo/samples/jfk.wav", "/tmp/test_alexa.wav"]:
        if os.path.exists(sample_wav):
            with wave.open(sample_wav, 'rb') as w:
                speech_neg = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
                for start in range(0, len(speech_neg) - target_len, 2000):
                    neg_clips.append(speech_neg[start:start + target_len])

    for _ in range(50):
        neg_clips.append(np.zeros(target_len, dtype=np.int16))

    neg_clips = np.array(neg_clips, dtype=np.int16)
    neg_embeddings = oww_model.preprocessor.embed_clips(neg_clips, batch_size=128)

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
    net = WakeNet()
    criterion = nn.BCEWithLogitsLoss()
    optimizer = optim.Adam(net.parameters(), lr=0.002, weight_decay=1e-4)

    epochs = 40
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
            logits = net(b_X)
            loss = criterion(logits, b_y)
            loss.backward()
            optimizer.step()
            epoch_loss += loss.item()

        if epoch % 10 == 0 or epoch == epochs:
            avg_loss = epoch_loss / max(1, n_batches)
            with torch.no_grad():
                probs = torch.sigmoid(net(X))
                acc = ((probs >= 0.5) == (y == 1.0)).float().mean().item() * 100.0
                pos_acc = (probs[:len(pos_embeddings)] >= 0.5).float().mean().item() * 100.0
                neg_acc = (probs[len(pos_embeddings):] < 0.5).float().mean().item() * 100.0
            print(f"    Epoch {epoch:02d}/{epochs:02d} | Perda: {avg_loss:.4f} | Acurácia Geral: {acc:.1f}% (Positivos: {pos_acc:.1f}% / Negativos: {neg_acc:.1f}%)")

    # 4. Export to ONNX
    print(f"\n  Exportando modelo 'VOID' para '{output_onnx}'...")
    export_model = ExportWakeNet(net)
    export_model.eval()
    dummy_input = torch.randn(1, 16, 96, dtype=torch.float32)

    torch.onnx.export(
        export_model,
        dummy_input,
        output_onnx,
        export_params=True,
        opset_version=18,
        do_constant_folding=True,
        input_names=['onnx::Flatten_0'],
        output_names=['13'],
        dynamic_axes={'onnx::Flatten_0': {0: 'batch_size'}, '13': {0: 'batch_size'}}
    )

    file_size_kb = os.path.getsize(output_onnx) / 1024.0
    print(f"  ✓ Modelo 'VOID' personalizado exportado com sucesso! ({file_size_kb:.1f} KB)")
    print("============================================================\n")

if __name__ == "__main__":
    main()
