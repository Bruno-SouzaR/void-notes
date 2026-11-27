use void_notes_core::stt::DirectiveFormatter;

#[test]
fn test_sanitizer_wake_word_prefix_variations() {
    let cases = [
        ("void comprar café amanhã", "Comprar café amanhã."),
        ("Void comprar café amanhã", "Comprar café amanhã."),
        ("hey void comprar café amanhã", "Comprar café amanhã."),
        ("Hey Void, comprar café amanhã", "Comprar café amanhã."),
        ("Ei void: comprar café amanhã", "Comprar café amanhã."),
        ("ok void - comprar café amanhã", "Comprar café amanhã."),
        ("okay void comprar café amanhã", "Comprar café amanhã."),
    ];

    for (input, expected) in cases {
        let result = DirectiveFormatter::format(input);
        assert_eq!(
            result,
            Some(expected.to_string()),
            "Failed for input: {}",
            input
        );
    }
}

#[test]
fn test_sanitizer_portuguese_accents_and_grammar() {
    let input = "void lembrar de pagar às dez horas a conta do condomínio e atenção às crianças";
    let expected = "Lembrar de pagar às dez horas a conta do condomínio e atenção às crianças.";
    let result = DirectiveFormatter::format(input);
    assert_eq!(result, Some(expected.to_string()));
}

#[test]
fn test_sanitizer_preserves_question_and_exclamation_marks() {
    assert_eq!(
        DirectiveFormatter::format("void onde está o arquivo?"),
        Some("Onde está o arquivo?".to_string())
    );
    assert_eq!(
        DirectiveFormatter::format("void atenção ao prazo de entrega!"),
        Some("Atenção ao prazo de entrega!".to_string())
    );
}

#[test]
fn test_sanitizer_rejects_whisper_silence_hallucinations() {
    let hallucinations = [
        "",
        "   ",
        "...",
        ".",
        "subtitles by community",
        "Subtitles by OpenSubtitles",
        "legendas pela comunidade",
        "obrigado por assistir ao vídeo",
        "thanks for watching!",
        "void",      // Wake word only
        "hey void.", // Wake word only with punctuation
    ];

    for input in hallucinations {
        let result = DirectiveFormatter::format(input);
        assert_eq!(
            result, None,
            "Expected None for hallucination input: '{}'",
            input
        );
    }
}
