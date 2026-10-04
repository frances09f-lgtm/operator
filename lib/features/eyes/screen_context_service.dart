import 'package:friday_app/features/eyes/eyes_service.dart';

enum ScreenContextMode {
  summarize,
  readAloud,
  qa,
  extractPhone,
  extractUrl,
  extractEmail,
}

/// A parsed UI node from the screen accessibility hierarchy.
class ScreenNode {
  final String label;
  final String? className;
  final bool isInteractive;
  final double? fx;
  final double? fy;

  const ScreenNode({
    required this.label,
    this.className,
    this.isInteractive = false,
    this.fx,
    this.fy,
  });
}

/// Comprehensive context representation of the active foreground screen.
class ScreenContext {
  final String packageName;
  final String appName;
  final List<ScreenNode> nodes;
  final List<String> visibleTexts;
  final String fullContent;
  final List<String> phoneNumbers;
  final List<String> urls;
  final List<String> emails;

  const ScreenContext({
    required this.packageName,
    required this.appName,
    required this.nodes,
    required this.visibleTexts,
    required this.fullContent,
    required this.phoneNumbers,
    required this.urls,
    required this.emails,
  });

  bool get isEmpty => visibleTexts.isEmpty;
}

/// Service providing parsing, summarization, and entity extraction
/// from the device's foreground screen.
class ScreenContextService {
  final EyesService _eyes;

  ScreenContextService({EyesService? eyes}) : _eyes = eyes ?? EyesService();

  /// Captures and parses the active screen context from the accessibility tree.
  Future<ScreenContext> captureContext({int maxNodes = 60}) async {
    final rawSummary = await _eyes.getSummary(maxNodes: maxNodes);
    return parseRawSummary(rawSummary);
  }

  /// Set of common overlay / assistant / system noise to filter out.
  static final Set<String> _ignoredLabels = {
    'friday',
    'operator',
    'listening...',
    'listening',
    'thinking...',
    'thinking',
    'thinking (smart mode)...',
    'ready',
    'ask me anything',
    'tap to speak',
    'tap to talk',
    'speak your command',
    'you said',
    'offline mode',
    'online mode',
    'back',
    'navigate up',
    'more options',
    'overflow',
    'battery',
    'wi-fi',
    'wifi',
    'signal',
    'cellular',
    'close',
    'dismiss',
    'clear text',
    'type a command...',
    'voice command',
    'speech',
    'mic',
    'microphone',
  };

  /// Parses raw Eyes string into a structured [ScreenContext].
  ScreenContext parseRawSummary(String rawSummary) {
    if (rawSummary.startsWith('EYES_ERROR') ||
        rawSummary.startsWith('EYES_EMPTY') ||
        rawSummary.trim().isEmpty) {
      return const ScreenContext(
        packageName: '',
        appName: '',
        nodes: [],
        visibleTexts: [],
        fullContent: '',
        phoneNumbers: [],
        urls: [],
        emails: [],
      );
    }

    var packageName = '';
    final lines = rawSummary.split('\n');
    final nodes = <ScreenNode>[];
    final visibleTexts = <String>[];

    final pkgExp = RegExp(r'^EYES\s+pkg=([^\s]+)');
    final labelExp = RegExp(r'"([^"]*)"');
    final clsExp = RegExp(r'-\[([^\]]+)\]');
    final fracExp = RegExp(r'@\[([\d.]+),([\d.]+)\]');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final pkgMatch = pkgExp.firstMatch(trimmed);
      if (pkgMatch != null) {
        packageName = pkgMatch.group(1) ?? '';
        continue;
      }

      if (trimmed.startsWith('-')) {
        final labelMatch = labelExp.firstMatch(trimmed);
        final label = labelMatch?.group(1)?.trim() ?? '';
        if (label.isEmpty) continue;

        final lowerLabel = label.toLowerCase();
        // Skip Friday overlay UI and meaningless navigation icons
        if (_ignoredLabels.contains(lowerLabel) ||
            lowerLabel.startsWith('listening') ||
            lowerLabel.startsWith('thinking') ||
            lowerLabel.startsWith('you said') ||
            lowerLabel.contains('speak your command')) {
          continue;
        }

        final clsMatch = clsExp.firstMatch(trimmed);
        final className = clsMatch?.group(1);

        final fracMatch = fracExp.firstMatch(trimmed);
        final fx = fracMatch != null ? double.tryParse(fracMatch.group(1) ?? '') : null;
        final fy = fracMatch != null ? double.tryParse(fracMatch.group(2) ?? '') : null;

        final lower = trimmed.toLowerCase();
        final isInteractive = lower.contains('tap') || lower.contains('edit');

        nodes.add(ScreenNode(
          label: label,
          className: className,
          isInteractive: isInteractive,
          fx: fx,
          fy: fy,
        ));

        // Avoid adding duplicate consecutive labels
        if (visibleTexts.isEmpty || visibleTexts.last != label) {
          visibleTexts.add(label);
        }
      }
    }

    final lowerPkg = packageName.toLowerCase();
    if (lowerPkg.contains('operator') || lowerPkg.contains('friday')) {
      return const ScreenContext(
        packageName: '',
        appName: '',
        nodes: [],
        visibleTexts: [],
        fullContent: '',
        phoneNumbers: [],
        urls: [],
        emails: [],
      );
    }

    final fullContent = visibleTexts.join(' ');
    final appName = _resolveAppName(packageName);
    final phoneNumbers = _extractPhoneNumbers(fullContent);
    final urls = _extractUrls(fullContent);
    final emails = _extractEmails(fullContent);

    return ScreenContext(
      packageName: packageName,
      appName: appName,
      nodes: nodes,
      visibleTexts: visibleTexts,
      fullContent: fullContent,
      phoneNumbers: phoneNumbers,
      urls: urls,
      emails: emails,
    );
  }

  /// Builds an intelligent, concise natural language summary of the screen.
  String generateOfflineSummary(ScreenContext context) {
    if (context.isEmpty) {
      return 'I cannot see any text on your current screen.';
    }

    final app = context.appName.isNotEmpty ? context.appName : 'your app';
    final texts = context.visibleTexts;

    // Separate prominent title / headline from body paragraphs
    final title = texts.first;
    final remaining = texts.skip(1).toList();

    // Specific app patterns
    final lowerApp = app.toLowerCase();
    if (lowerApp.contains('whatsapp') || lowerApp.contains('message')) {
      final contact = title;
      final msgs = remaining.where((t) => t.length > 3).take(2).join('; ');
      if (msgs.isNotEmpty) {
        return 'You are in WhatsApp with $contact. Recent message: "$msgs".';
      }
      return 'You are in WhatsApp viewing a conversation with $contact.';
    }

    if (lowerApp.contains('youtube')) {
      return 'You are watching "$title" on YouTube.';
    }

    if (lowerApp.contains('chrome') || lowerApp.contains('browser')) {
      final snippet = remaining.where((t) => t.length > 15).take(1).join();
      if (snippet.isNotEmpty) {
        final cleanSnippet = snippet.length > 80 ? '${snippet.substring(0, 77)}...' : snippet;
        return 'In Chrome, you are reading "$title". It says: "$cleanSnippet".';
      }
      return 'In Chrome, you are viewing "$title".';
    }

    if (lowerApp.contains('settings')) {
      final options = remaining.take(3).join(', ');
      if (options.isNotEmpty) {
        return 'You are in Settings on $title with options for $options.';
      }
      return 'You are in Settings on $title.';
    }

    // Generic summarization
    if (texts.length == 1) {
      return 'In $app, your screen shows "$title".';
    }

    // Extract key sentences / headlines
    final substantial = texts.where((t) => t.length > 10).take(2).toList();
    if (substantial.isNotEmpty) {
      final body = substantial.join(' ');
      final cleanBody = body.length > 90 ? '${body.substring(0, 87)}...' : body;
      return 'In $app, you are viewing "$title". Summary: $cleanBody';
    }

    final preview = texts.take(3).join(', ');
    return 'In $app, your screen displays: $preview.';
  }

  /// Builds a formatted prompt with screen context for the local LLM.
  String buildLlmScreenPrompt({
    required ScreenContext context,
    required String userQuery,
  }) {
    final buf = StringBuffer()
      ..writeln('System: You are Friday, an AI screen assistant. Summarize what is on the user\'s screen in 1-2 clear, natural sentences. Do NOT list raw button names or UI icons.')
      ..writeln('Active App: ${context.appName.isNotEmpty ? context.appName : context.packageName}')
      ..writeln('Screen Text:');

    for (final text in context.visibleTexts.take(25)) {
      buf.writeln('- $text');
    }

    if (context.phoneNumbers.isNotEmpty) {
      buf.writeln('Phone Numbers: ${context.phoneNumbers.join(', ')}');
    }
    if (context.urls.isNotEmpty) {
      buf.writeln('Links: ${context.urls.join(', ')}');
    }

    buf.writeln('\nUser Query: $userQuery');
    buf.writeln('Summary:');
    return buf.toString();
  }

  String _resolveAppName(String packageName) {
    if (packageName.isEmpty) return '';
    final lower = packageName.toLowerCase();
    if (lower.contains('chrome') || lower.contains('browser')) return 'Chrome';
    if (lower.contains('whatsapp')) return 'WhatsApp';
    if (lower.contains('youtube')) return 'YouTube';
    if (lower.contains('gmail') || lower.contains('mail')) return 'Gmail';
    if (lower.contains('spotify')) return 'Spotify';
    if (lower.contains('twitter') || lower.contains('x.com')) return 'X';
    if (lower.contains('instagram')) return 'Instagram';
    if (lower.contains('maps')) return 'Maps';
    if (lower.contains('settings')) return 'Settings';
    final parts = packageName.split('.');
    return parts.isNotEmpty ? parts.last : packageName;
  }

  List<String> _extractPhoneNumbers(String text) {
    final phoneExp = RegExp(
      r'(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}|\b\d{10}\b',
    );
    return phoneExp
        .allMatches(text)
        .map((m) => m.group(0)?.trim() ?? '')
        .where((s) => s.isNotEmpty && s.length >= 7)
        .toSet()
        .toList();
  }

  List<String> _extractUrls(String text) {
    final urlExp = RegExp(
      r'https?:\/\/(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
      caseSensitive: false,
    );
    return urlExp
        .allMatches(text)
        .map((m) => m.group(0)?.trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  List<String> _extractEmails(String text) {
    final emailExp = RegExp(
      r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
    );
    return emailExp
        .allMatches(text)
        .map((m) => m.group(0)?.trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }
}
