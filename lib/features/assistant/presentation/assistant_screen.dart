import 'package:flutter/material.dart';
import 'package:friday_app/features/assistant/presentation/assistant_controller.dart';
import 'package:friday_app/features/assistant/presentation/widgets/assistant_orb.dart';
import 'package:friday_app/features/automation/presentation/custom_commands_screen.dart';
import 'package:friday_app/services/voice/adaptive_voice_command_service.dart';

class AssistantScreen extends StatefulWidget {
  final AssistantController controller;

  const AssistantScreen({super.key, required this.controller});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.initializeModel();
    widget.controller.checkSmartModelAvailable();
    widget.controller.initializeSpeech();
    widget.controller.initializeTts();
    widget.controller.initializeAutomation();
    widget.controller.initializeAssist();
    widget.controller.checkGmailStatus();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _textController.text;
    _textController.clear();
    widget.controller.processCommand(text);
  }

  void _showSettingsSheet(AssistantController ctrl) {
    final outerContext = context;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: ctrl,
          builder: (context, _) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle + title header
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.settings, size: 20, color: Colors.white70),
                          const SizedBox(width: 10),
                          const Text(
                            'Settings',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            tooltip: 'Close',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white12, height: 1),
                      const SizedBox(height: 16),

                      // Voice responses box (moved from main screen)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.record_voice_over, size: 18, color: Colors.white70),
                                const SizedBox(width: 8),
                                const Text(
                                  'Voice responses',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Switch(
                                  value: ctrl.isTtsEnabled,
                                  onChanged: ctrl.setTtsEnabled,
                                  activeThumbColor: Colors.blueAccent,
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                children: [
                                  const Text(
                                    'Enable spoken replies',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    ctrl.isTtsEnabled ? 'On' : 'Off',
                                    style: TextStyle(
                                      color: ctrl.isTtsEnabled ? Colors.greenAccent : Colors.white38,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (ctrl.isTtsEnabled) ...[
                              const SizedBox(height: 12),
                              const Divider(color: Colors.white12, height: 1),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text(
                                    'Speed',
                                    style: TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: ctrl.ttsSpeechRate.clamp(0.25, 1.0).toDouble(),
                                      min: 0.25,
                                      max: 1.0,
                                      divisions: 3,
                                      activeColor: Colors.blueAccent,
                                      label: '${(ctrl.ttsSpeechRate * 100).round()}%',
                                      onChanged: ctrl.setTtsSpeechRate,
                                    ),
                                  ),
                                  Text(
                                    '${(ctrl.ttsSpeechRate * 100).round()}%',
                                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Speech Engine setting: Whistle (Offline On-Device) vs. Android System Speech
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.mic, size: 18, color: Colors.blueAccent),
                                SizedBox(width: 8),
                                Text(
                                  'Speech Engine',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Choose your voice recognition engine for speech commands:',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            // Option 1: Whistle (Offline On-Device)
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                if (!ctrl.isWhistleEngineActive) {
                                  ctrl.setVoiceEngine(VoiceEngineType.whistle);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: ctrl.isWhistleEngineActive
                                      ? Colors.blueAccent.withValues(alpha: 0.15)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: ctrl.isWhistleEngineActive
                                        ? Colors.blueAccent
                                        : Colors.white12,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      ctrl.isWhistleEngineActive
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      size: 18,
                                      color: ctrl.isWhistleEngineActive
                                          ? Colors.blueAccent
                                          : Colors.white38,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Whistle (Offline On-Device)',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            ctrl.isVoiceModelDownloaded
                                                ? '16.9 MB model installed • 100% private offline'
                                                : 'Model not installed (30 MB download required)',
                                            style: TextStyle(
                                              color: ctrl.isVoiceModelDownloaded
                                                  ? Colors.white38
                                                  : Colors.amberAccent,
                                              fontSize: 11,
                                            ),
                                          ),
                                          if (ctrl.isDownloadingVoiceModel) ...[
                                            const SizedBox(height: 6),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: ctrl.voiceModelDownloadProgress > 0
                                                    ? ctrl.voiceModelDownloadProgress
                                                    : null,
                                                minHeight: 4,
                                                backgroundColor: Colors.white12,
                                                valueColor: const AlwaysStoppedAnimation(Colors.blueAccent),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Downloading... ${(ctrl.voiceModelDownloadProgress * 100).round()}%',
                                              style: const TextStyle(color: Colors.blueAccent, fontSize: 10),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (!ctrl.isVoiceModelDownloaded && !ctrl.isDownloadingVoiceModel)
                                      ElevatedButton(
                                        onPressed: ctrl.downloadVoiceModel,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blueAccent,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                        ),
                                        child: const Text('Download', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      )
                                    else if (ctrl.isWhistleEngineActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.greenAccent.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'ACTIVE',
                                          style: TextStyle(
                                            color: Colors.greenAccent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Option 2: Android System Speech
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                if (ctrl.isWhistleEngineActive) {
                                  ctrl.setVoiceEngine(VoiceEngineType.systemSpeech);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: !ctrl.isWhistleEngineActive
                                      ? Colors.blueAccent.withValues(alpha: 0.15)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: !ctrl.isWhistleEngineActive
                                        ? Colors.blueAccent
                                        : Colors.white12,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      !ctrl.isWhistleEngineActive
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      size: 18,
                                      color: !ctrl.isWhistleEngineActive
                                          ? Colors.blueAccent
                                          : Colors.white38,
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Android System Speech',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'Built-in SpeechRecognizer • System speech services',
                                            style: TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!ctrl.isWhistleEngineActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'ACTIVE',
                                          style: TextStyle(
                                            color: Colors.blueAccent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Volume & brightness step box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.tune, size: 18, color: Colors.white70),
                                SizedBox(width: 8),
                                Text(
                                  'Volume & brightness steps',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'How much each â€œincrease / decreaseâ€ voice command changes.',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text(
                                  'Volume',
                                  style: TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: ctrl.volumeStep.clamp(1, 30).toDouble(),
                                    min: 1,
                                    max: 30,
                                    divisions: 29,
                                    activeColor: Colors.blueAccent,
                                    label: '${ctrl.volumeStep}%',
                                    onChanged: (v) => ctrl.setVolumeStep(v.round()),
                                  ),
                                ),
                                Text(
                                  '${ctrl.volumeStep}%',
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Text(
                                  'Brightness',
                                  style: TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: ctrl.brightnessStep.clamp(1, 30).toDouble(),
                                    min: 1,
                                    max: 30,
                                    divisions: 29,
                                    activeColor: Colors.blueAccent,
                                    label: '${ctrl.brightnessStep}%',
                                    onChanged: (v) => ctrl.setBrightnessStep(v.round()),
                                  ),
                                ),
                                Text(
                                  '${ctrl.brightnessStep}%',
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // My Commands box (moved from main screen into Settings)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.auto_awesome, size: 16, color: Colors.blueAccent),
                                const SizedBox(width: 8),
                                const Text(
                                  'My Commands',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${ctrl.customCommands.length}',
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (ctrl.customCommands.isEmpty)
                              const Text(
                                'No teachable commands yet.\nCreate one to replay taps via voice.',
                                style: TextStyle(color: Colors.white38, fontSize: 12),
                              )
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: ctrl.customCommands.take(6).map((c) => ActionChip(
                                  label: Text(c.displayName, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                  backgroundColor: const Color(0xFF2A2A2A),
                                  side: const BorderSide(color: Colors.white12),
                                  onPressed: () {
                                    Navigator.of(sheetContext).pop();
                                    final text = c.phraseTemplate.replaceAllMapped(RegExp(r'\{\{\s*\w+\s*\}\}'), (m) => 'John');
                                    ctrl.processCommand(text);
                                  },
                                )).toList(),
                              ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.auto_awesome, size: 16),
                                label: const Text('Manage Commands'),
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();
                                  Navigator.of(outerContext).push(
                                    MaterialPageRoute(builder: (_) => CustomCommandsScreen(controller: ctrl)),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blueAccent,
                                  side: const BorderSide(color: Colors.blueAccent),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Gmail box (moved from main screen into Settings)
                      _buildGmailBox(ctrl),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Done',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.bug_report, color: Colors.white70),
                tooltip: 'Manual test',
                onPressed: () =>
                    Navigator.of(context).pushNamed('/friday-test'),
              ),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white70),
                tooltip: 'Settings',
                onPressed: () => _showSettingsSheet(ctrl),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title Header
                    const Text(
                      'FRIDAY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Local AI Assistant',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Model Status Badge
                    _buildModelStatusBadge(ctrl),
                    _buildModelDownloadArea(ctrl),
                    _buildSmartModelArea(ctrl),
                    const SizedBox(height: 16),

                    // Jarvis-style reactive orb
                    Center(
                      child: AssistantOrb(controller: ctrl, size: 220),
                    ),
                    const SizedBox(height: 16),

                    // FRIDAY spoken response â€” centered just below orb (moved from bottom)
                    _buildCenterStatus(ctrl),
                    const SizedBox(height: 10),

                    // Explicit assistant state label
                    _buildStateLabel(ctrl),
                    const SizedBox(height: 12),

                    // Collected automation result
                    if (ctrl.lastAutomationResult != null && ctrl.lastAutomationResult!.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blueAccent.withOpacity(0.4))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [Icon(Icons.assignment_turned_in, size: 14, color: Colors.blueAccent), SizedBox(width: 6), Text('Automation Result', style: TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.w600))]),
                            const SizedBox(height: 6),
                            SelectableText(ctrl.lastAutomationResult!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Input Field
                    TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      enabled: !ctrl.isProcessing,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: ctrl.isListening
                            ? 'Listening... speak now'
                            : 'What do you want me to do?',
                        hintStyle: TextStyle(
                          color: ctrl.isListening
                              ? Colors.redAccent
                              : Colors.white.withAlpha(128),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 16),

                    // Command Buttons: Mic + Open
                    Row(
                      children: [
                        Expanded(child: _buildMicButton(ctrl)),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: ctrl.isProcessing ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: ctrl.isProcessing
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Send',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Divider
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 20),

                    // Status and Results Area â€” FRIDAY response now shown above near orb
                    if (ctrl.streamingReply != null &&
                        ctrl.streamingReply!.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.purpleAccent.withOpacity(0.4)),
                        ),
                        child: Text(
                          ctrl.streamingReply!,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                    if (ctrl.chatHistory.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.psychology,
                                    size: 14, color: Colors.purpleAccent),
                                const SizedBox(width: 6),
                                const Text('Smart Chat',
                                    style: TextStyle(
                                        color: Colors.purpleAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                                const Spacer(),
                                GestureDetector(
                                  onTap: ctrl.isProcessing
                                      ? null
                                      : () => ctrl.clearChatHistory(),
                                  child: const Text('Clear',
                                      style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ...ctrl.chatHistory.take(6).map((m) {
                              final isUser = m['role'] == 'user';
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: Text(
                                  '${isUser ? "You" : "FRIDAY"}: ${m['text']}',
                                  style: TextStyle(
                                    color: isUser
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                    if (ctrl.lastUserCommand != null && ctrl.lastUserCommand!.isNotEmpty) ...[
                      const Text(
                        'You:',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ctrl.lastUserCommand!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Debug panel: shows exactly what the local model emitted
                    // when a command could not be understood.
                    if (ctrl.lastProcessingError != null) ...[
                      const Divider(color: Colors.white12),
                      const SizedBox(height: 8),
                      if (ctrl.lastRawModelOutput != null) ...[
                        const Text(
                          'Model output:',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: SelectableText(
                            ctrl.lastRawModelOutput!,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        'Error: ${ctrl.lastProcessingError}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCenterStatus(AssistantController ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        ctrl.statusMessage,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _getStatusColor(ctrl.statusMessage),
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildMicButton(AssistantController ctrl) {
    final enabled = !ctrl.isProcessing && ctrl.isSpeechAvailable;
    final listening = ctrl.isListening;

    return Tooltip(
      message: listening ? 'Stop listening' : 'Give a command by voice',
      child: OutlinedButton(
        onPressed: enabled ? () => ctrl.toggleListening() : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: listening ? Colors.redAccent : null,
          side: BorderSide(
            color: listening
                ? Colors.redAccent
                : ctrl.isSpeechAvailable
                    ? Colors.blueAccent
                    : Colors.white24,
          ),
          foregroundColor: listening ? Colors.white : Colors.blueAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: listening
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.stop_circle, size: 20),
                  SizedBox(width: 8),
                  Text('Stop', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mic, size: 20),
                  SizedBox(width: 8),
                  Text('Mic', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }

  Widget _buildStateLabel(AssistantController ctrl) {
    final (icon, label, color) = switch (ctrl.phase) {
      AssistantPhase.listening => (Icons.mic, 'Listening...', Colors.redAccent),
      AssistantPhase.processing => (Icons.psychology, 'Processing...', Colors.blueAccent),
      AssistantPhase.speaking => (Icons.graphic_eq, 'Speaking...', Colors.greenAccent),
      AssistantPhase.opening => (Icons.open_in_new, 'Opening...', Colors.greenAccent),
      AssistantPhase.error => (Icons.error_outline, 'Error', Colors.redAccent),
      AssistantPhase.idle => (Icons.circle, 'Idle', Colors.white54),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: ctrl.isSpeaking ? () => ctrl.stopSpeaking() : null,
          child: Text(
            ctrl.isSpeaking ? 'Speaking... (tap to stop)' : label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModelStatusBadge(AssistantController ctrl) {
    Color badgeColor;
    String badgeText;
    IconData icon;

    switch (ctrl.modelStatus) {
      case ModelStatus.ready:
        badgeColor = Colors.greenAccent;
        badgeText = 'Local AI Ready';
        icon = Icons.check_circle_outline;
        break;
      case ModelStatus.loading:
        badgeColor = Colors.amberAccent;
        badgeText = 'Loading Model...';
        icon = Icons.hourglass_top;
        break;
      case ModelStatus.missing:
        badgeColor = Colors.orangeAccent;
        badgeText = 'Model Missing (place .gguf in app storage)';
        icon = Icons.warning_amber_rounded;
        break;
      case ModelStatus.error:
        badgeColor = Colors.redAccent;
        badgeText = 'Model Error';
        icon = Icons.error_outline;
        break;
      case ModelStatus.notChecked:
        badgeColor = Colors.grey;
        badgeText = 'Checking...';
        icon = Icons.sync;
        break;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: badgeColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            badgeText,
            style: TextStyle(
              color: badgeColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (ctrl.modelStatus == ModelStatus.missing || ctrl.modelStatus == ModelStatus.error) ...[
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Retry model check',
            onPressed: () => ctrl.initializeModel(),
          ),
        ],
      ],
    );
  }

  /// Shows a progress bar while the model downloads, or a button to kick off
  /// the download when no model is installed. Hidden otherwise.
  Widget _buildModelDownloadArea(AssistantController ctrl) {
    if (ctrl.modelStatus != ModelStatus.missing &&
        ctrl.modelStatus != ModelStatus.error) {
      return const SizedBox.shrink();
    }

    if (ctrl.isDownloadingModel) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ctrl.modelDownloadProgress,
                minHeight: 6,
                backgroundColor: Colors.white12,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Downloading AI model... ${(ctrl.modelDownloadProgress * 100).round()}%',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: OutlinedButton.icon(
        onPressed: ctrl.isProcessing ? null : () => ctrl.downloadModel(),
        icon: const Icon(Icons.download, size: 18),
        label: const Text('Download AI Model (~230 MB)'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.blueAccent,
          disabledForegroundColor: Colors.white24,
          side: const BorderSide(color: Colors.blueAccent),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  /// Shows a progress bar while the model downloads, or a button to kick off
  /// the download when no model is installed. Hidden otherwise.
  Widget _buildSmartModelArea(AssistantController ctrl) {
    if (ctrl.isChatAvailable) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.psychology, size: 12, color: Colors.purpleAccent),
            SizedBox(width: 4),
            Text('Smart Chat Ready',
                style: TextStyle(color: Colors.purpleAccent, fontSize: 11)),
          ],
        ),
      );
    }
    if (ctrl.isDownloadingChatModel) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ctrl.chatDownloadProgress,
                minHeight: 6,
                backgroundColor: Colors.white12,
                color: Colors.purpleAccent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Downloading smart model... ${(ctrl.chatDownloadProgress * 100).round()}%',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }
    if (ctrl.isChatLoading) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: OutlinedButton.icon(
          onPressed: () => ctrl.cancelSmartChat(),
          icon: const Icon(Icons.stop_circle, size: 18),
          label: const Text('Smart mode loading... tap to cancel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.purpleAccent,
            side: const BorderSide(color: Colors.purpleAccent),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: OutlinedButton.icon(
        onPressed: ctrl.isProcessing ? null : () => ctrl.downloadChatModel(),
        icon: const Icon(Icons.psychology, size: 18),
        label: const Text('Download Smart Model (~1GB) for Q&A'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.purpleAccent,
          disabledForegroundColor: Colors.white24,
          side: const BorderSide(color: Colors.purpleAccent),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

/// Gmail (read-only) connection card inside Settings: connect/disconnect,
  /// background unread preview and the last failure detail.
  Widget _buildGmailBox(AssistantController ctrl) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ctrl.isGmailConnected
              ? Colors.greenAccent.withOpacity(0.4)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mail_outline, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              const Text(
                'Gmail (read-only)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (ctrl.isGmailConnected
                          ? Colors.greenAccent
                          : Colors.white12)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  ctrl.isGmailConnected ? 'Connected' : 'Not linked',
                  style: TextStyle(
                    color: ctrl.isGmailConnected
                        ? Colors.greenAccent
                        : Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ctrl.isGmailConnected
                ? 'Say "read my unread mails" â€” background check, no Gmail app opened.'
                : 'Link your account so FRIDAY can read unread mail. '
                    'FRIDAY can only read â€” it never sends or deletes mail.',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (ctrl.gmailLastError != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: Text(
                'Last error: ${ctrl.gmailLastError}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 10),
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (ctrl.isGmailConnected)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: ctrl.isProcessing
                        ? null
                        : () => ctrl.processCommand('read my unread mails'),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh inbox'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.greenAccent,
                      side: const BorderSide(color: Colors.greenAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ctrl.disconnectGmail(),
                    icon: const Icon(Icons.link_off, size: 16),
                    label: const Text('Disconnect'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    ctrl.isConnectingGmail ? null : () => ctrl.connectGmail(),
                icon: ctrl.isConnectingGmail
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_link, size: 16),
                label: Text(ctrl.isConnectingGmail
                    ? 'Connecting Gmail...'
                    : 'Connect Gmail'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.greenAccent,
                  disabledForegroundColor: Colors.white24,
                  side: const BorderSide(color: Colors.greenAccent),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          if (ctrl.isGmailConnected && ctrl.lastEmails.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...ctrl.lastEmails.take(5).map((m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '${m.from} â€” ${m.subject}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
          ],
        ],
      ),
    );
  }
  Color _getStatusColor(String message) {
    if (message.startsWith('Opening')) return Colors.greenAccent;
    if (message.endsWith('is ON.')) return Colors.greenAccent;
    if (message.endsWith('is OFF.')) return Colors.white70;
    if (message == 'Playing.' ||
        message == 'Paused.' ||
        message == 'Resuming.' ||
        message == 'Skipping.' ||
        message == 'Going back.' ||
        message == 'Stopped.') {
      return Colors.greenAccent;
    }
    if (message == 'Ready') return Colors.white70;
    if (message == 'Thinking...') return Colors.blueAccent;
    if (message.startsWith('Listening') || message.startsWith('You said')) {
      return Colors.redAccent;
    }
    if (message.contains('isn\'t installed') ||
        message.contains('not installed') ||
        message.contains('isn\'t available') ||
        message.contains('not available')) {
      return Colors.redAccent;
    }
    if (message == 'I can only open apps and control media, volume, and brightness right now.' ||
        message == 'I couldn\'t understand that command.' ||
        message == 'Please tell me which app to open.' ||
        message == 'I couldn\'t control the media.') {
      return Colors.redAccent;
    }
    return Colors.white;
  }
}
