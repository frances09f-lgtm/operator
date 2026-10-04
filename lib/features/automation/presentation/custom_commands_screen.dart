import 'package:flutter/material.dart';
import 'package:friday_app/features/assistant/presentation/assistant_controller.dart';
import 'package:friday_app/features/automation/models/custom_command.dart';
import 'package:friday_app/features/automation/models/tap_step.dart';
import 'package:friday_app/features/automation/services/automation_service.dart';

class CustomCommandsScreen extends StatefulWidget {
  final AssistantController controller;

  const CustomCommandsScreen({super.key, required this.controller});

  @override
  State<CustomCommandsScreen> createState() => _CustomCommandsScreenState();
}

class _CustomCommandsScreenState extends State<CustomCommandsScreen> {
  bool _isRecording = false;
  bool _checkingPermission = false;

  @override
  void initState() {
    super.initState();
    widget.controller.refreshCustomCommands();
  }

  Future<void> _addExampleCommands() async {
    final examples = _buildExamples();
    for (final cmd in examples) {
      await widget.controller.saveCustomCommand(cmd);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Example commands added')),
      );
    }
  }

  List<CustomCommand> _buildExamples() {
    final now = DateTime.now();
    return [
      CustomCommand(
        id: 'whatsapp_check_${now.millisecondsSinceEpoch}',
        phraseTemplate: 'check whatsapp message',
        displayName: 'Check WhatsApp messages',
        targetPackage: 'com.whatsapp',
        steps: const [
          TapStep(type: TapStepType.openApp, targetPackage: 'com.whatsapp', delayAfterMs: 1200),
          TapStep(type: TapStepType.wait, durationMs: 800, delayAfterMs: 0),
          TapStep(type: TapStepType.collect, collectSelector: '', collectCount: 5, delayAfterMs: 0),
        ],
        createdAt: now,
        updatedAt: now,
        description: 'Opens WhatsApp and collects latest messages',
      ),
      CustomCommand(
        id: 'whatsapp_read_contact_${now.millisecondsSinceEpoch + 1}',
        phraseTemplate: 'what did {{contact}} say',
        displayName: 'Read chat with {{contact}}',
        targetPackage: 'com.whatsapp',
        steps: const [
          TapStep(type: TapStepType.openApp, targetPackage: 'com.whatsapp', delayAfterMs: 1200),
          TapStep(type: TapStepType.wait, durationMs: 700, delayAfterMs: 0),
          TapStep(type: TapStepType.findByDesc, selectorValue: 'Search', contains: true, xPct: 0.85, yPct: 0.12, delayAfterMs: 400),
          TapStep(type: TapStepType.inputText, inputValue: '{{contact}}', delayAfterMs: 600),
          TapStep(type: TapStepType.wait, durationMs: 700, delayAfterMs: 0),
          TapStep(type: TapStepType.findByText, selectorValue: '{{contact}}', contains: true, delayAfterMs: 500),
          TapStep(type: TapStepType.wait, durationMs: 800, delayAfterMs: 0),
          TapStep(type: TapStepType.collect, collectSelector: '', collectCount: 5, delayAfterMs: 0),
        ],
        createdAt: now,
        updatedAt: now,
        description: 'Searches contact and reads last messages. Say "what did John say"',
      ),
      CustomCommand(
        id: 'snapchat_location_${now.millisecondsSinceEpoch + 2}',
        phraseTemplate: 'check location of {{contact}} on snapchat',
        displayName: 'Check {{contact}} location on Snapchat',
        targetPackage: 'com.snapchat.android',
        steps: const [
          TapStep(type: TapStepType.openApp, targetPackage: 'com.snapchat.android', delayAfterMs: 1500),
          TapStep(type: TapStepType.wait, durationMs: 1000, delayAfterMs: 0),
          // Snap Map is usually the location button; use coordinate fallback if selector fails
          TapStep(type: TapStepType.findByDesc, selectorValue: 'Map', contains: true, xPct: 0.15, yPct: 0.9, delayAfterMs: 600),
          TapStep(type: TapStepType.wait, durationMs: 1200, delayAfterMs: 0),
          TapStep(type: TapStepType.findByText, selectorValue: 'Search', contains: true, xPct: 0.5, yPct: 0.12, delayAfterMs: 400),
          TapStep(type: TapStepType.inputText, inputValue: '{{contact}}', delayAfterMs: 600),
          TapStep(type: TapStepType.findByText, selectorValue: '{{contact}}', contains: true, delayAfterMs: 600),
          TapStep(type: TapStepType.wait, durationMs: 1500, delayAfterMs: 0),
          TapStep(type: TapStepType.collect, collectSelector: '', collectCount: 8, delayAfterMs: 0),
        ],
        createdAt: now,
        updatedAt: now,
        description: 'Opens Snap Map, searches contact, collects location info',
      ),
    ];
  }

  Future<void> _showCreateDialog() async {
    final phraseCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final packageCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('New Teachable Command', style: TextStyle(color: Colors.white)),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: phraseCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Voice phrase (use {{param}})',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintText: 'e.g. check location of {{contact}} on snapchat',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintText: 'e.g. Check Snapchat location',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: packageCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Target app package (optional)',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintText: 'e.g. com.snapchat.android',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tip: Use {{contact}} for names. Steps are added after creation. You can also use Record to capture taps.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == true) {
      final phrase = phraseCtrl.text.trim();
      var displayName = nameCtrl.text.trim();
      if (displayName.isEmpty) displayName = phrase;
      final pkg = packageCtrl.text.trim().isEmpty ? null : packageCtrl.text.trim();
      final now = DateTime.now();
      final cmd = CustomCommand(
        id: 'cmd_${now.millisecondsSinceEpoch}',
        phraseTemplate: phrase,
        displayName: displayName,
        targetPackage: pkg,
        steps: [],
        createdAt: now,
        updatedAt: now,
      );
      await widget.controller.saveCustomCommand(cmd);
      if (!mounted) return;
      // Open step editor immediately
      await _openStepEditor(cmd);
    }
  }

  Future<void> _openStepEditor(CustomCommand command) async {
    // Reload latest
    await widget.controller.refreshCustomCommands();
    final latest = widget.controller.customCommands.firstWhere((c) => c.id == command.id, orElse: () => command);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StepEditorScreen(controller: widget.controller, command: latest)),
    );
    setState(() {});
  }

  Future<void> _delete(CustomCommand cmd) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete command?', style: TextStyle(color: Colors.white)),
        content: Text('Delete "${cmd.displayName}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm == true) {
      await widget.controller.deleteCustomCommand(cmd.id);
      setState(() {});
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      setState(() => _checkingPermission = true);
      try {
        final svc = MethodChannelAutomationService();
        final steps = await svc.stopRecording();
        setState(() {
          _isRecording = false;
          _checkingPermission = false;
        });
        if (!mounted) return;
        if (steps.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No taps recorded')));
          return;
        }
        // Ask which command to save to, or create new
        await _showSaveRecordedSteps(steps);
      } catch (e) {
        setState(() {
          _isRecording = false;
          _checkingPermission = false;
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stop failed: $e')));
      }
      return;
    }

    setState(() => _checkingPermission = true);
    try {
      final svc = MethodChannelAutomationService();
      final enabled = await svc.isAccessibilityEnabled();
      if (!enabled) {
        setState(() => _checkingPermission = false);
        if (!mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('Accessibility Required', style: TextStyle(color: Colors.white)),
            content: const Text('Teachable commands need Accessibility Service. Open settings to enable FRIDAY?',
                style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open Settings')),
            ],
          ),
        );
        if (go == true) await svc.requestAccessibilitySettings();
        return;
      }
      final overlayOk = await svc.isOverlayGranted();
      if (!overlayOk) {
        setState(() => _checkingPermission = false);
        if (!mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text('Overlay Permission', style: TextStyle(color: Colors.white)),
            content: const Text('Need overlay permission to show REC button. Open settings?',
                style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open Settings')),
            ],
          ),
        );
        if (go == true) await svc.requestOverlayPermission();
        return;
      }

      await svc.startRecording();
      setState(() {
        _isRecording = true;
        _checkingPermission = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording started - perform your taps, then tap Stop'), duration: Duration(seconds: 4)),
        );
      }
    } catch (e) {
      setState(() => _checkingPermission = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Record failed: $e')));
    }
  }

  Future<void> _showSaveRecordedSteps(List<TapStep> steps) async {
    final cmds = widget.controller.customCommands;
    String? selectedId;
    final phraseCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Save Recorded Taps', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${steps.length} steps captured', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                if (cmds.isNotEmpty) ...[
                  const Align(alignment: Alignment.centerLeft, child: Text('Append to existing:', style: TextStyle(color: Colors.white54, fontSize: 12))),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selectedId,
                    hint: const Text('Select command', style: TextStyle(color: Colors.white38)),
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('— Create new —', style: TextStyle(color: Colors.white70))),
                      ...cmds.map((c) => DropdownMenuItem(value: c.id, child: Text(c.displayName, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setDlg(() => selectedId = v),
                  ),
                  const SizedBox(height: 12),
                  const Text('Or create new:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
                TextField(
                  controller: phraseCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Phrase (if new)',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintText: 'e.g. check location of {{contact}} on snapchat',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Display name (if new)',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              onPressed: () async {
                // Infer target package from recorded steps (openApp step or first packageName)
                String? inferredPkg;
                for (final s in steps) {
                  if (s.type == TapStepType.openApp && s.targetPackage != null && s.targetPackage!.isNotEmpty) {
                    inferredPkg = s.targetPackage;
                    break;
                  }
                }
                if (selectedId != null) {
                  final existing = cmds.firstWhere((c) => c.id == selectedId);
                  // Preserve existing targetPackage unless inferred is more specific
                  final pkg = existing.targetPackage ?? inferredPkg;
                  final updated = existing.copyWith(
                    steps: [...existing.steps, ...steps],
                    targetPackage: pkg,
                  );
                  await widget.controller.saveCustomCommand(updated);
                } else {
                  final phrase = phraseCtrl.text.trim();
                  if (phrase.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter phrase for new command')));
                    return;
                  }
                  var dName = nameCtrl.text.trim();
                  if (dName.isEmpty) dName = phrase;
                  final now = DateTime.now();
                  final newCmd = CustomCommand(
                    id: 'cmd_${now.millisecondsSinceEpoch}',
                    phraseTemplate: phrase,
                    displayName: dName,
                    targetPackage: inferredPkg,
                    steps: steps,
                    createdAt: now,
                    updatedAt: now,
                  );
                  await widget.controller.saveCustomCommand(newCmd);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
              },
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _testRun(CustomCommand cmd) async {
    // Simple test with first param example
    Map<String, String> params = {};
    if (cmd.paramNames.isNotEmpty) {
      final ctrl = TextEditingController(text: 'John');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text('Test "${cmd.displayName}"', style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter ${cmd.paramNames.join(", ")}:', style: const TextStyle(color: Colors.white70)),
              TextField(controller: ctrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Run')),
          ],
        ),
      );
      if (ok != true) return;
      for (final p in cmd.paramNames) params[p] = ctrl.text.trim();
    }
    final text = cmd.paramNames.isEmpty ? cmd.phraseTemplate : cmd.phraseTemplate.replaceAllMapped(RegExp(r'\{\{\s*(\w+)\s*\}\}'), (m) => params[m.group(1)!.toLowerCase()] ?? m.group(0)!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Running "$text"...')));
    await widget.controller.processCommand(text);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final cmds = widget.controller.customCommands;
        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            elevation: 0,
            title: const Text('Teachable Commands', style: TextStyle(color: Colors.white)),
            iconTheme: const IconThemeData(color: Colors.white70),
            actions: [
              if (_checkingPermission)
                const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              IconButton(icon: const Icon(Icons.add), tooltip: 'New', onPressed: _showCreateDialog),
            ],
          ),
          body: Column(
            children: [
              // Recording bar
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: _isRecording ? Colors.redAccent : Colors.white12)),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(_isRecording ? Icons.fiber_manual_record : Icons.radio_button_unchecked, color: _isRecording ? Colors.redAccent : Colors.white54, size: 18),
                        const SizedBox(width: 8),
                        Text(_isRecording ? 'Recording taps...' : 'Teach by tapping', style: TextStyle(color: _isRecording ? Colors.redAccent : Colors.white, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: _checkingPermission ? null : _toggleRecording,
                          icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow, size: 18),
                          label: Text(_isRecording ? 'Stop' : 'Record'),
                          style: ElevatedButton.styleFrom(backgroundColor: _isRecording ? Colors.redAccent : Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                        ),
                      ],
                    ),
                    if (_isRecording) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Perform taps in target app, then tap Stop. Overlay REC button shown.', style: TextStyle(color: Colors.white54, fontSize: 11))),
                    if (!_isRecording) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Tap Record, then do your steps (e.g. open Snapchat -> Map -> search John). Save to replay via voice.', style: TextStyle(color: Colors.white38, fontSize: 11))),
                  ],
                ),
              ),
              // Example button
              if (cmds.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: OutlinedButton.icon(
                    onPressed: _addExampleCommands,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Add Example Commands (WhatsApp / Snapchat)'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.blueAccent, side: const BorderSide(color: Colors.blueAccent)),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: cmds.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('No teachable commands yet.\n\nCreate one with + or tap Record to capture taps.\n\nExample phrase: "check location of {{contact}} on snapchat"', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                        itemCount: cmds.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final cmd = cmds[i];
                          return Container(
                            decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
                            child: ListTile(
                              title: Text(cmd.displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text('"${cmd.phraseTemplate}"', style: const TextStyle(color: Colors.blueAccent, fontSize: 12)),
                                  const SizedBox(height: 2),
                                  Text('${cmd.steps.length} steps • ${cmd.targetPackage ?? "any app"} • params: ${cmd.paramNames.isEmpty ? "none" : cmd.paramNames.join(", ")}',
                                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, color: Colors.white54, size: 18),
                                color: const Color(0xFF2A2A2A),
                                onSelected: (v) {
                                  if (v == 'edit') _openStepEditor(cmd);
                                  else if (v == 'delete') _delete(cmd);
                                  else if (v == 'test') _testRun(cmd);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'test', child: Text('Test Run', style: TextStyle(color: Colors.white))),
                                  PopupMenuItem(value: 'edit', child: Text('Edit Steps', style: TextStyle(color: Colors.white))),
                                  PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
                                ],
                              ),
                              onTap: () => _openStepEditor(cmd),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _showCreateDialog,
            backgroundColor: Colors.blueAccent,
            icon: const Icon(Icons.add),
            label: const Text('New Command'),
          ),
        );
      },
    );
  }
}

class StepEditorScreen extends StatefulWidget {
  final AssistantController controller;
  final CustomCommand command;

  const StepEditorScreen({super.key, required this.controller, required this.command});

  @override
  State<StepEditorScreen> createState() => _StepEditorScreenState();
}

class _StepEditorScreenState extends State<StepEditorScreen> {
  late CustomCommand _cmd;

  @override
  void initState() {
    super.initState();
    _cmd = widget.command;
  }

  Future<void> _save() async {
    await widget.controller.saveCustomCommand(_cmd.copyWith(steps: _cmd.steps));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  void _updateSteps(List<TapStep> newSteps) {
    setState(() {
      _cmd = _cmd.copyWith(steps: newSteps);
    });
  }

  Future<void> _addStep() async {
    final step = await showDialog<TapStep>(
      context: context,
      builder: (ctx) => const StepTypePicker(),
    );
    if (step != null) {
      final newSteps = [..._cmd.steps, step];
      _updateSteps(newSteps);
      await widget.controller.saveCustomCommand(_cmd.copyWith(steps: newSteps));
    }
  }

  Future<void> _editStep(int index) async {
    final existing = _cmd.steps[index];
    final edited = await showDialog<TapStep>(
      context: context,
      builder: (ctx) => StepEditDialog(initial: existing),
    );
    if (edited != null) {
      final newSteps = [..._cmd.steps];
      newSteps[index] = edited;
      _updateSteps(newSteps);
      await widget.controller.saveCustomCommand(_cmd.copyWith(steps: newSteps));
    }
  }

  Future<void> _deleteStep(int index) async {
    final newSteps = [..._cmd.steps]..removeAt(index);
    _updateSteps(newSteps);
    await widget.controller.saveCustomCommand(_cmd.copyWith(steps: newSteps));
  }

  void _reorder(int oldIdx, int newIdx) {
    if (newIdx > oldIdx) newIdx--;
    final newSteps = [..._cmd.steps];
    final item = newSteps.removeAt(oldIdx);
    newSteps.insert(newIdx, item);
    _updateSteps(newSteps);
    widget.controller.saveCustomCommand(_cmd.copyWith(steps: newSteps));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: Text('Edit: ${_cmd.displayName}', style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white70),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _save, tooltip: 'Save'),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Phrase: "${_cmd.phraseTemplate}"', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text('Package: ${_cmd.targetPackage ?? "any"} • ${ _cmd.steps.length} steps', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 4),
                const Text('Use {{contact}} in phrase and inputValue for dynamic names.', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: _cmd.steps.isEmpty
                ? const Center(
                    child: Text(
                      'No steps yet. Tap + to add.\n\nStep types: tap, findByText/Desc/Id, inputText, wait, openApp, collect, swipe, back',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                    itemCount: _cmd.steps.length,
                    onReorder: _reorder,
                    itemBuilder: (ctx, i) {
                      final s = _cmd.steps[i];
                      return Container(
                        key: ValueKey('step_$i'),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.blueAccent, radius: 14, child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11))),
                          title: Text(_stepTitle(s), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                          subtitle: Text(_stepSubtitle(s), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit, size: 16, color: Colors.white54), onPressed: () => _editStep(i)),
                              IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.redAccent), onPressed: () => _deleteStep(i)),
                              const Icon(Icons.drag_handle, size: 16, color: Colors.white24),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addStep, backgroundColor: Colors.blueAccent, child: const Icon(Icons.add)),
    );
  }

  String _stepTitle(TapStep s) {
    switch (s.type) {
      case TapStepType.tap: return 'Tap at ${(s.xPct ?? 0.5).toStringAsFixed(2)}, ${(s.yPct ?? 0.5).toStringAsFixed(2)}';
      case TapStepType.swipe: return 'Swipe';
      case TapStepType.inputText: return 'Input "${s.inputValue ?? ""}"';
      case TapStepType.wait: return 'Wait ${s.durationMs ?? s.delayAfterMs ?? 500}ms';
      case TapStepType.findByText: return 'Find Text "${s.selectorValue ?? ""}"${s.contains ? " (contains)" : ""}';
      case TapStepType.findByDesc: return 'Find Desc "${s.selectorValue ?? ""}"${s.contains ? " (contains)" : ""}';
      case TapStepType.findById: return 'Find ID "${s.selectorValue ?? ""}"';
      case TapStepType.openApp: return 'Open App ${s.targetPackage ?? ""}';
      case TapStepType.collect: return 'Collect texts (${s.collectCount ?? 5})';
      case TapStepType.back: return 'Back';
    }
  }

  String _stepSubtitle(TapStep s) {
    final parts = <String>[];
    if (s.delayAfterMs != null) parts.add('delay ${s.delayAfterMs}ms');
    if (s.collectSelector != null && s.collectSelector!.isNotEmpty) parts.add('selector "${s.collectSelector}"');
    return parts.join(' • ');
  }
}

class StepTypePicker extends StatelessWidget {
  const StepTypePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final types = [
      ('Tap (coordinates)', TapStepType.tap),
      ('Find by Text + Tap', TapStepType.findByText),
      ('Find by Desc + Tap', TapStepType.findByDesc),
      ('Find by ID + Tap', TapStepType.findById),
      ('Input Text', TapStepType.inputText),
      ('Wait / Delay', TapStepType.wait),
      ('Open App', TapStepType.openApp),
      ('Collect Texts', TapStepType.collect),
      ('Swipe', TapStepType.swipe),
      ('Back Button', TapStepType.back),
    ];
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Choose Step Type', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: types.map((e) => ListTile(
            title: Text(e.$1, style: const TextStyle(color: Colors.white)),
            onTap: () {
              TapStep step;
              switch (e.$2) {
                case TapStepType.tap: step = const TapStep(type: TapStepType.tap, xPct: 0.5, yPct: 0.5, delayAfterMs: 400); break;
                case TapStepType.findByText: step = const TapStep(type: TapStepType.findByText, selectorValue: 'Search', contains: true, xPct: 0.5, yPct: 0.12, delayAfterMs: 500); break;
                case TapStepType.findByDesc: step = const TapStep(type: TapStepType.findByDesc, selectorValue: 'Search', contains: true, xPct: 0.5, yPct: 0.12, delayAfterMs: 500); break;
                case TapStepType.findById: step = const TapStep(type: TapStepType.findById, selectorValue: 'com.whatsapp:id/search', delayAfterMs: 500); break;
                case TapStepType.inputText: step = const TapStep(type: TapStepType.inputText, inputValue: '{{contact}}', delayAfterMs: 500); break;
                case TapStepType.wait: step = const TapStep(type: TapStepType.wait, durationMs: 800, delayAfterMs: 0); break;
                case TapStepType.openApp: step = const TapStep(type: TapStepType.openApp, targetPackage: 'com.whatsapp', delayAfterMs: 1200); break;
                case TapStepType.collect: step = const TapStep(type: TapStepType.collect, collectSelector: '', collectCount: 5, delayAfterMs: 0); break;
                case TapStepType.swipe: step = const TapStep(type: TapStepType.swipe, xPct: 0.5, yPct: 0.8, x2Pct: 0.5, y2Pct: 0.3, durationMs: 300, delayAfterMs: 400); break;
                case TapStepType.back: step = const TapStep(type: TapStepType.back, delayAfterMs: 400); break;
              }
              Navigator.pop(context, step);
            },
          )).toList(),
        ),
      ),
    );
  }
}

class StepEditDialog extends StatefulWidget {
  final TapStep initial;
  const StepEditDialog({super.key, required this.initial});

  @override
  State<StepEditDialog> createState() => _StepEditDialogState();
}

class _StepEditDialogState extends State<StepEditDialog> {
  late TapStep _step;
  late TextEditingController _selectorCtrl;
  late TextEditingController _inputCtrl;
  late TextEditingController _packageCtrl;
  late TextEditingController _xCtrl;
  late TextEditingController _yCtrl;
  late TextEditingController _x2Ctrl;
  late TextEditingController _y2Ctrl;
  late TextEditingController _delayCtrl;
  late TextEditingController _durCtrl;
  late TextEditingController _collectCtrl;
  late TextEditingController _countCtrl;
  bool _contains = false;

  @override
  void initState() {
    super.initState();
    _step = widget.initial;
    _contains = _step.contains;
    _selectorCtrl = TextEditingController(text: _step.selectorValue ?? '');
    _inputCtrl = TextEditingController(text: _step.inputValue ?? '');
    _packageCtrl = TextEditingController(text: _step.targetPackage ?? '');
    _xCtrl = TextEditingController(text: (_step.xPct ?? 0.5).toString());
    _yCtrl = TextEditingController(text: (_step.yPct ?? 0.5).toString());
    _x2Ctrl = TextEditingController(text: (_step.x2Pct ?? 0.5).toString());
    _y2Ctrl = TextEditingController(text: (_step.y2Pct ?? 0.3).toString());
    _delayCtrl = TextEditingController(text: (_step.delayAfterMs ?? 400).toString());
    _durCtrl = TextEditingController(text: (_step.durationMs ?? 800).toString());
    _collectCtrl = TextEditingController(text: _step.collectSelector ?? '');
    _countCtrl = TextEditingController(text: (_step.collectCount ?? 5).toString());
  }

  @override
  void dispose() {
    _selectorCtrl.dispose();
    _inputCtrl.dispose();
    _packageCtrl.dispose();
    _xCtrl.dispose();
    _yCtrl.dispose();
    _x2Ctrl.dispose();
    _y2Ctrl.dispose();
    _delayCtrl.dispose();
    _durCtrl.dispose();
    _collectCtrl.dispose();
    _countCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text('Edit Step: ${_step.type.name}', style: const TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_step.type == TapStepType.findByText || _step.type == TapStepType.findByDesc || _step.type == TapStepType.findById) ...[
              TextField(controller: _selectorCtrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: _step.type == TapStepType.findById ? 'View ID' : 'Text/Desc', labelStyle: const TextStyle(color: Colors.white70), enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)))),
              Row(children: [Checkbox(value: _contains, onChanged: (v) => setState(() => _contains = v ?? false), activeColor: Colors.blueAccent), const Text('Contains (substring)', style: TextStyle(color: Colors.white70, fontSize: 12))]),
              const SizedBox(height: 8),
              Row(children: [Expanded(child: TextField(controller: _xCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Fallback x% 0-1', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))))), const SizedBox(width: 8), Expanded(child: TextField(controller: _yCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Fallback y% 0-1', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)))))]),
            ],
            if (_step.type == TapStepType.tap) ...[
              Row(children: [Expanded(child: TextField(controller: _xCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'x% 0-1', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))))), const SizedBox(width: 8), Expanded(child: TextField(controller: _yCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'y% 0-1', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)))))]),
            ],
            if (_step.type == TapStepType.swipe) ...[
              Row(children: [Expanded(child: TextField(controller: _xCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'x% start', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))))), const SizedBox(width: 8), Expanded(child: TextField(controller: _yCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'y% start', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)))))]),
              const SizedBox(height: 8),
              Row(children: [Expanded(child: TextField(controller: _x2Ctrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'x% end', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24))))), const SizedBox(width: 8), Expanded(child: TextField(controller: _y2Ctrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'y% end', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)))))]),
              const SizedBox(height: 8),
              TextField(controller: _durCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Duration ms', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)))),
            ],
            if (_step.type == TapStepType.inputText) ...[
              TextField(controller: _inputCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Text to input ({{contact}} allowed)', labelStyle: TextStyle(color: Colors.white70), hintText: '{{contact}}', hintStyle: TextStyle(color: Colors.white38), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)))),
            ],
            if (_step.type == TapStepType.wait) ...[
              TextField(controller: _durCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Wait ms', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)))),
            ],
            if (_step.type == TapStepType.openApp) ...[
              TextField(controller: _packageCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Package (e.g. com.snapchat.android)', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)))),
            ],
            if (_step.type == TapStepType.collect) ...[
              TextField(controller: _collectCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Selector filter (empty = all)', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)))),
              const SizedBox(height: 8),
              TextField(controller: _countCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Max count', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)))),
            ],
            const SizedBox(height: 12),
            TextField(controller: _delayCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Delay after ms', labelStyle: TextStyle(color: Colors.white70), enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
          onPressed: () {
            double? dx = double.tryParse(_xCtrl.text);
            double? dy = double.tryParse(_yCtrl.text);
            double? dx2 = double.tryParse(_x2Ctrl.text);
            double? dy2 = double.tryParse(_y2Ctrl.text);
            int? delay = int.tryParse(_delayCtrl.text);
            int? dur = int.tryParse(_durCtrl.text);
            int? cnt = int.tryParse(_countCtrl.text);
            final edited = TapStep(
              type: _step.type,
              xPct: dx,
              yPct: dy,
              x2Pct: dx2,
              y2Pct: dy2,
              selectorValue: _selectorCtrl.text.trim().isEmpty ? null : _selectorCtrl.text.trim(),
              contains: _contains,
              inputValue: _inputCtrl.text.trim().isEmpty ? null : _inputCtrl.text,
              targetPackage: _packageCtrl.text.trim().isEmpty ? null : _packageCtrl.text.trim(),
              durationMs: dur,
              delayAfterMs: delay,
              collectSelector: _collectCtrl.text.trim().isEmpty ? null : _collectCtrl.text.trim(),
              collectCount: cnt,
            );
            Navigator.pop(context, edited);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
