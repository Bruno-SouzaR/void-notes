/// Directive text formatting and sanitization pipeline.
#[derive(Debug, Clone)]
pub struct DirectiveFormatter;

impl DirectiveFormatter {
    /// List of wake word prefixes to strip from the beginning of transcripts.
    const WAKE_WORD_PREFIXES: &'static [&'static str] = &[
        "hey void",
        "ei void",
        "ok void",
        "okay void",
        "void",
    ];

    /// Hallucinations or filler phrases commonly output by small Whisper models during silence.
    const HALLUCINATION_BLACKLIST: &'static [&'static str] = &[
        "subtitles by",
        "legendas pela",
        "obrigado por assistir",
        "thanks for watching",
        "...",
        ".",
    ];

    /// Cleans and formats raw speech-to-text output into a canonical Directive string.
    ///
    /// Returns `None` if the text is empty or matched a known Whisper silence hallucination.
    pub fn format(raw_text: &str) -> Option<String> {
        let trimmed = raw_text.trim();
        if trimmed.is_empty() {
            return None;
        }

        // Check against known silence hallucinations
        let lower = trimmed.to_lowercase();
        for &hallucination in Self::HALLUCINATION_BLACKLIST {
            if lower == hallucination || lower.starts_with(hallucination) {
                return None;
            }
        }

        // Strip wake word prefix if present at start
        let mut stripped = trimmed;
        for &prefix in Self::WAKE_WORD_PREFIXES {
            if lower.starts_with(prefix) {
                stripped = &trimmed[prefix.len()..];
                break;
            }
        }

        // Clean leading punctuation, whitespace, and filler chars
        let cleaned = stripped
            .trim_start_matches(|c: char| c.is_whitespace() || c == ',' || c == '.' || c == '-' || c == ':')
            .trim();

        if cleaned.is_empty() || cleaned.len() < 2 {
            return None;
        }

        // Capitalize the first Unicode character
        let mut chars = cleaned.chars();
        let first = chars.next()?;
        let mut formatted = first.to_uppercase().collect::<String>();
        formatted.push_str(chars.as_str());

        // Ensure closing punctuation
        if !formatted.ends_with(['.', '!', '?']) {
            formatted.push('.');
        }

        Some(formatted)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_strips_wake_word_and_capitalizes() {
        let input = "void lembrar de comprar pão amanhã";
        let output = DirectiveFormatter::format(input);
        assert_eq!(output, Some("Lembrar de comprar pão amanhã.".to_string()));
    }

    #[test]
    fn test_format_strips_hey_void_with_comma() {
        let input = "Hey Void, pagar o boleto do condomínio";
        let output = DirectiveFormatter::format(input);
        assert_eq!(output, Some("Pagar o boleto do condomínio.".to_string()));
    }

    #[test]
    fn test_format_preserves_existing_punctuation() {
        let input = "void onde está o arquivo de configuração?";
        let output = DirectiveFormatter::format(input);
        assert_eq!(output, Some("Onde está o arquivo de configuração?".to_string()));
    }

    #[test]
    fn test_format_rejects_hallucinations_and_empty() {
        assert_eq!(DirectiveFormatter::format(""), None);
        assert_eq!(DirectiveFormatter::format("   "), None);
        assert_eq!(DirectiveFormatter::format("..."), None);
        assert_eq!(DirectiveFormatter::format("Subtitles by community"), None);
        assert_eq!(DirectiveFormatter::format("void"), None); // only wake word
    }
}
