use std::fs::File;
use std::io::{self, Read, Write};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::Instant;

use void_notes_core::feedback::FeedbackProfile;
use void_notes_core::kws::MockWakeWordDetector;
use void_notes_core::stt::WhisperCliRecognizer;
use void_notes_core::VoidService;

/// Spawns a background pw-record process writing 16kHz mono s16 PCM to a WAV file.
fn start_pw_record(wav_path: &PathBuf) -> anyhow::Result<Child> {
    let child = Command::new("pw-record")
        .arg("--rate")
        .arg("16000")
        .arg("--channels")
        .arg("1")
        .arg("--format")
        .arg("s16")
        .arg(wav_path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    Ok(child)
}

/// Reads a 16-bit mono 16 kHz WAV file and converts it to normalized f32 samples.
fn read_wav_as_f32(path: &PathBuf) -> anyhow::Result<Vec<f32>> {
    let mut file = File::open(path)?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)?;

    if buffer.len() < 44 {
        return Ok(Vec::new());
    }

    // Skip 44-byte WAV header and read 16-bit PCM little-endian samples
    let pcm_bytes = &buffer[44..];
    let mut samples = Vec::with_capacity(pcm_bytes.len() / 2);

    for chunk in pcm_bytes.as_chunks::<2>().0 {
        let sample_i16 = i16::from_le_bytes([chunk[0], chunk[1]]);
        samples.push(sample_i16 as f32 / 32768.0);
    }

    Ok(samples)
}

fn main() -> anyhow::Result<()> {
    println!("============================================================");
    println!("  void-notes — Live Microphone Accuracy & Precision Test");
    println!("============================================================");

    let use_small = std::env::args().any(|a| a == "--small" || a == "small");
    let model_path = if use_small {
        PathBuf::from("models/ggml-small-q5_1.bin")
    } else {
        PathBuf::from("models/ggml-base-q5_1.bin")
    };
    let binary_path = PathBuf::from("bin/whisper-cli");
    let db_path = PathBuf::from("data/live_test.db");
    let notes_dir = PathBuf::from("notes");
    std::fs::create_dir_all("data")?;
    std::fs::create_dir_all(&notes_dir)?;

    if !binary_path.exists() {
        eprintln!("Error: whisper-cli not found at {:?}", binary_path);
        std::process::exit(1);
    }
    if !model_path.exists() {
        eprintln!("Error: model not found at {:?}", model_path);
        std::process::exit(1);
    }

    println!("[1/3] Initializing engine with real WhisperCliRecognizer...");
    println!("      Model: {:?}", model_path);
    println!("      Binary: {:?}", binary_path);
    println!("      Database: {:?}", db_path);

    let conn = rusqlite::Connection::open(&db_path)?;
    let recognizer = WhisperCliRecognizer::new(&binary_path, &model_path)
        .with_language("pt")
        .with_threads(2)
        .with_initial_prompt("Anotações em português brasileiro, fala natural e contínua.");
    // KWS armed to accept the live phrase
    let mut kws = MockWakeWordDetector::new(Default::default());
    kws.arm_trigger();

    let service = VoidService::from_connection(
        conn,
        &notes_dir,
        FeedbackProfile::Normal,
        Box::new(kws),
        Box::new(recognizer),
    )?;
    println!("      ✓ Engine initialized successfully.");

    println!("\n[2/3] Preparando gravação do microfone ao vivo...");
    println!("      Instrução: Pressione ENTER para INICIAR a gravação.");
    println!("      Fale uma frase natural em português (ex: 'Lembrar de comprar pão e ligar para o médico').");
    println!("      Pressione ENTER novamente para PARAR e transcrever.");

    print!("\n>>> Pressione [ENTER] quando estiver pronto para falar: ");
    io::stdout().flush()?;
    let mut line = String::new();
    io::stdin().read_line(&mut line)?;

    let temp_wav = std::env::temp_dir().join(format!("void_live_{}.wav", uuid::Uuid::new_v4()));
    let mut recording_process = start_pw_record(&temp_wav)?;
    let start_rec = Instant::now();

    println!("\n🎙️  GRAVANDO... [Fale no microfone agora]");
    print!(">>> Pressione [ENTER] para parar a gravação: ");
    io::stdout().flush()?;
    let mut line2 = String::new();
    io::stdin().read_line(&mut line2)?;

    // Stop recording process
    let _ = recording_process.kill();
    let _ = recording_process.wait();
    let rec_duration = start_rec.elapsed();

    println!("\n[3/3] Gravação finalizada ({:.2}s). Processando áudio...", rec_duration.as_secs_f32());

    let f32_samples = read_wav_as_f32(&temp_wav)?;
    let _ = std::fs::remove_file(&temp_wav);

    if f32_samples.is_empty() {
        println!("⚠️ Nenhum áudio capturado.");
        return Ok(());
    }

    println!("      Total de amostras capturadas: {} ({:.2}s de áudio PCM a 16 kHz)",
        f32_samples.len(),
        f32_samples.len() as f32 / 16000.0
    );

    // Process through PriorityOverride to trigger transcription
    let start_transcription = Instant::now();
    println!("      Executando inferência com whisper.cpp (2 threads)...");

    // Ingest the samples via the recognizer
    let (note, actions) = {
        // Trigger priority session
        service.trigger_priority_override();

        // Feed samples in chunks of 480 (30ms)
        let chunk_size = 480;
        let mut completed_note = None;
        let mut final_actions = Vec::new();

        for chunk in f32_samples.chunks(chunk_size) {
            let (n, a) = service.process_audio_chunk(chunk, 30)?;
            if n.is_some() {
                completed_note = n;
                final_actions = a;
                break;
            }
        }

        // Feed trailing silence to close endpoint if not closed yet
        if completed_note.is_none() {
            let silence = vec![0.0f32; 480];
            for _ in 0..55 {
                let (n, a) = service.process_audio_chunk(&silence, 30)?;
                if n.is_some() {
                    completed_note = n;
                    final_actions = a;
                    break;
                }
            }
        }

        (completed_note, final_actions)
    };

    let inference_time = start_transcription.elapsed();

    println!("\n============================================================");
    println!("  RESULTADO DA TRANSCRIÇÃO");
    println!("============================================================");

    if let Some(n) = note {
        println!("  ✓ Texto Transcrito e Formatado:");
        println!("    \"{}\"", n.content);
        println!("\n  Detalhes Técnicos:");
        println!("    - ID da Nota (UUID v4): {}", n.id);
        println!("    - Duração do Áudio:     {:.2}s", n.audio_duration_ms as f32 / 1000.0);
        println!("    - Tempo de Inferência:  {:.2}s (RTF: {:.2}x)",
            inference_time.as_secs_f32(),
            inference_time.as_secs_f32() / (n.audio_duration_ms as f32 / 1000.0)
        );
        println!("    - Ações de Feedback:    {:?}", actions);
        println!("    - Gravado no SQLite:    {:?}", db_path);

        let today_str = chrono::Utc::now().format("%Y-%m-%d").to_string();
        let md_path = notes_dir.join(format!("{}.md", today_str));
        println!("    - Espelhado no Markdown: {:?}", md_path);

        if md_path.exists() {
            let content = std::fs::read_to_string(&md_path)?;
            println!("\n------ Conteúdo do Arquivo Markdown ({:?}) ------", md_path);
            println!("{}", content.trim());
            println!("--------------------------------------------------");
        }
    } else {
        println!("  ⚠️ A fala não foi reconhecida ou foi classificada como silêncio/ruído.");
    }

    println!("============================================================");

    Ok(())
}
