/// Structure representing the extracted visual representation of a directive note.
class ParsedDirective {
  final String title;
  final List<String> items;
  final bool isList;

  const ParsedDirective({
    required this.title,
    required this.items,
    required this.isList,
  });
}

/// Unified heuristic parser for directive content, checklists, and titles.
class DirectiveParser {
  DirectiveParser._();

  /// Determines whether a directive's content represents a checklist or shopping list.
  static bool isChecklist(String content) {
    final lower = content.toLowerCase();
    return lower.contains('lista') ||
        lower.contains('mercado') ||
        lower.contains('compras') ||
        lower.contains('comprar') ||
        content.contains('- [ ]') ||
        content.contains('- [x]');
  }

  /// Parses raw directive text into a structured title, item list, and checklist flag.
  static ParsedDirective parse(String rawContent) {
    var text = rawContent.trim();
    final isList = isChecklist(text);

    if (isList) {
      final prefixRegex = RegExp(
        r'^(cria uma |fazer uma |nova |nota para o |nota para um )?lista( de compras| de mercado)?[:., -]*',
        caseSensitive: false,
      );
      final match = prefixRegex.firstMatch(text);
      String title = 'Lista de Compras';
      if (match != null) {
        text = text.substring(match.end).trim();
      }

      List<String> rawItems = [];
      if (text.contains('\n')) {
        rawItems = text.split('\n');
      } else if (text.contains(',') || text.contains(';')) {
        rawItems = text.split(RegExp(r'[,;]'));
      } else {
        rawItems = [text];
      }

      final List<String> items = [];
      for (var item in rawItems) {
        var cleaned = item.trim().replaceAll(RegExp(r'^\s*[-*•]\s*(\[[ x]\]\s*)?'), '').trim();
        if (cleaned.contains(' e ') && !cleaned.toLowerCase().startsWith('e ')) {
          for (var s in cleaned.split(' e ')) {
            final st = s.trim().replaceAll(RegExp(r'\.+$'), '');
            if (st.isNotEmpty) items.add(st);
          }
        } else {
          final st = cleaned.replaceAll(RegExp(r'\.+$'), '');
          if (st.isNotEmpty) items.add(st);
        }
      }

      if (items.isEmpty && text.isNotEmpty) {
        items.add(text);
      }
      return ParsedDirective(title: title, items: items, isList: true);
    } else {
      String title;
      String body;

      // Check for sentence boundary with punctuation followed by space
      final sentenceMatch = RegExp(r'([.!?])\s+').firstMatch(text);
      if (sentenceMatch != null) {
        title = text.substring(0, sentenceMatch.start + 1).trim();
        body = text.substring(sentenceMatch.end).trim();
      } else {
        final clean = text.replaceAll(RegExp(r'[.!?]+$'), '');
        final words = clean.split(' ');
        if (words.length > 5) {
          title = words.take(5).join(' ');
          body = words.skip(5).join(' ');
          if (text.endsWith('.')) {
            body = '$body.';
          }
        } else {
          title = text;
          body = '';
        }
      }
      return ParsedDirective(
        title: title,
        items: body.isNotEmpty ? [body] : const [],
        isList: false,
      );
    }
  }
}
