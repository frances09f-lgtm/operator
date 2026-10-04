import 'dart:io';
import 'package:flutter/material.dart';
import 'package:friday_app/core/constants/app_constants.dart';
import 'package:friday_app/features/agent/friday_agent.dart';
import 'package:friday_app/features/eyes/eyes_service.dart';
import 'package:friday_app/features/hands/hands_service.dart';
import 'package:friday_app/services/local_llm/friday_brain.dart';
import 'package:friday_app/services/local_llm/model_downloader.dart';

/// Simple manual test screen for the Friday skeleton.
///
/// Eyes, Brain, Hands, and the minimal agent loop are functional. Nothing
/// runs automatically; every action needs a tap. Hands actions additionally
/// need Arm, and refuse banking/payment apps.
class ManualTestScreen extends StatefulWidget {
  const ManualTestScreen({super.key});

  @override
  State<ManualTestScreen> createState() => _ManualTestScreenState();
}

class _ManualTestScreenState extends State<ManualTestScreen> {
  final EyesService _eyes = EyesService();
  final FridayBrain _brain = FridayBrain();
  final HandsService _hands = HandsService();
  final TextEditingController _handsField = TextEditingController();
  final TextEditingController _goalField = TextEditingController();
  bool _eyesBusy = false;
  String _eyesOutput = 'Not checked yet.';
  bool _brainBusy = false;
  String? _brainModelPath;
  String _brainOutput = 'Model not checked yet.';
  bool _handsBusy = false;
  bool _handsArmed = false;
  String _handsOutput = 'Disarmed. Tap Arm to enable test actions.';
  bool _agentBusy = false;
  String _agentOutput = 'Idle. Load the 135M model, Arm Hands, type a goal.';

  @override
  void dispose() {
    _handsField.dispose();
    _goalField.dispose();
    super.dispose();
  }

  Future<void> _checkEnabled() async {
    setState(() {
      _eyesBusy = true;
      _eyesOutput = 'Checking...';
    });
    final enabled = await _eyes.isEnabled();
    if (!mounted) return;
    setState(() {
      _eyesBusy = false;
      _eyesOutput =
          enabled ? 'Accessibility service: ENABLED' : 'Accessibility service: DISABLED';
    });
  }

  Future<void> _getSummary() async {
    setState(() {
      _eyesBusy = true;
      _eyesOutput = 'Reading...';
    });
    final summary = await _eyes.getSummary();
    if (!mounted) return;
    setState(() {
      _eyesBusy = false;
      _eyesOutput = summary;
    });
  }

  Future<void> _brainFind() async {
    setState(() {
      _brainBusy = true;
      _brainOutput = 'Searching for SmolLM2-135M...';
    });
    final path = await _brain.findCommandModel();
    if (!mounted) return;
    if (path == null) {
      setState(() {
        _brainBusy = false;
        _brainModelPath = null;
        _brainOutput = 'MODEL_MISSING: place SmolLM2-135M-Instruct-Q4_K_M.gguf (~105MB) in app storage or tap "Download 135M".';
      });
      return;
    }
    final file = File(path);
    final size = await file.length();
    const expected = 105454432;
    final isExact = size == expected;
    setState(() {
      _brainBusy = false;
      _brainModelPath = path;
      _brainOutput = 'Found: $path\n'
          'Exact size: $size bytes (${(size / (1024 * 1024)).toStringAsFixed(2)} MB)\n'
          '${isExact ? "Status: COMPLETE & VERIFIED" : "WARNING: File size differs from official $expected bytes! (Possible corruption)"}\n'
          'Context size: ${AppConstants.inferenceContextSize}';
    });
  }

  Future<void> _brainDownload() async {
    setState(() {
      _brainBusy = true;
      _brainOutput = 'Connecting to Hugging Face to download SmolLM2-135M...';
    });
    try {
      final downloader = ModelDownloader(url: AppConstants.modelDownloadUrl);
      final dest = await _brain.getPrimaryModelPath();
      await downloader.downloadTo(
        destinationPath: dest,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _brainOutput = 'Downloading: ${(p * 100).toStringAsFixed(1)}%\nURL: ${AppConstants.modelDownloadUrl}';
            });
          }
        },
      );
      if (!mounted) return;
      final file = File(dest);
      final size = await file.length();
      setState(() {
        _brainBusy = false;
        _brainModelPath = dest;
        _brainOutput = 'Download complete!\nPath: $dest\nSize: $size bytes. Ready to load.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _brainBusy = false;
        _brainOutput = 'Download failed: $e\nURL: ${AppConstants.modelDownloadUrl}';
      });
    }
  }

  Future<void> _brainLoad() async {
    final path = _brainModelPath;
    if (path == null) {
      setState(() {
        _brainOutput = 'MODEL_MISSING: find the model first.';
      });
      return;
    }
    setState(() {
      _brainBusy = true;
      _brainOutput = 'Loading (on-device, may take a while)...';
    });
    try {
      await _brain.loadCommandModel(path);
      if (!mounted) return;
      setState(() {
        _brainBusy = false;
        _brainOutput = 'Ready (${_brain.mode ?? 'command'}). Tap Infer to test.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _brainBusy = false;
        _brainOutput = 'LOAD_FAILED: $e';
      });
    }
  }

  Future<void> _brainInfer() async {
    if (!_brain.isReady) {
      setState(() {
        _brainOutput = 'MODEL_MISSING: load the model first.';
      });
      return;
    }
    setState(() {
      _brainBusy = true;
      _brainOutput = 'Thinking on-device...';
    });
    try {
      final sw = Stopwatch()..start();
      final out = await _brain.generateRaw(
        system: 'Follow the pattern strictly. Output only the requested word.\nUser: Say hi\nAssistant: hi\nUser: Say test\nAssistant: test',
        user: 'Say ok',
        maxTokens: 16,
      );
      sw.stop();
      if (!mounted) return;
      var clean = out.trim();
      // Remove any repeated assistant prefixes
      if (clean.toLowerCase().startsWith('assistant:')) {
        clean = clean.substring(10).trim();
      }
      setState(() {
        _brainBusy = false;
        _brainOutput = clean.isEmpty
            ? 'LOAD_FAILED: empty reply'
            : '[${sw.elapsedMilliseconds} ms] Echo test: $clean';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _brainBusy = false;
        _brainOutput = 'LOAD_FAILED: $e';
      });
    }
  }

  Future<void> _brainInferCommand() async {
    if (!_brain.isReady) {
      setState(() {
        _brainOutput = 'MODEL_MISSING: load the model first.';
      });
      return;
    }
    setState(() {
      _brainBusy = true;
      _brainOutput = 'Classifying "open youtube" on-device...';
    });
    try {
      final sw = Stopwatch()..start();
      final out = await _brain.infer('open youtube');
      sw.stop();
      if (!mounted) return;
      setState(() {
        _brainBusy = false;
        _brainOutput = '[${sw.elapsedMilliseconds} ms] Command: "open youtube"\n$out';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _brainBusy = false;
        _brainOutput = 'INFER_FAILED: $e';
      });
    }
  }

  Future<void> _brainInferAgentAction() async {
    if (!_brain.isReady) {
      setState(() {
        _brainOutput = 'MODEL_MISSING: load the model first.';
      });
      return;
    }
    setState(() {
      _brainBusy = true;
      _brainOutput = 'Deciding action on-device...';
    });
    try {
      final sw = Stopwatch()..start();
      final out = await _brain.generateRaw(
        system: FridayAgent.systemPrompt,
        user: FridayAgent.buildPrompt('tap search', const [
          AgentCandidate(index: 1, label: 'Home', canTap: true, canEdit: false, fx: 0.5, fy: 0.5),
          AgentCandidate(index: 2, label: 'Search', canTap: true, canEdit: false, fx: 0.5, fy: 0.3),
        ]),
        maxTokens: 32,
      );
      sw.stop();
      if (!mounted) return;
      final decision = FridayAgent.parseDecision(out);
      final decisionText = decision != null
          ? (decision.verb == 'TAP'
              ? 'TAP ${decision.index}'
              : (decision.verb == 'TYPE'
                  ? 'TYPE ${decision.index} "${decision.text}"'
                  : 'DONE'))
          : out.trim();
      setState(() {
        _brainBusy = false;
        _brainOutput = '[${sw.elapsedMilliseconds} ms] Decision: $decisionText (raw: "${out.trim()}")';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _brainBusy = false;
        _brainOutput = 'AGENT_ACTION_FAILED: $e';
      });
    }
  }

  Future<void> _handsToggleArm() async {
    setState(() {
      _handsBusy = true;
    });
    final res = _handsArmed ? await _hands.disarm() : await _hands.arm();
    if (!mounted) return;
    setState(() {
      _handsBusy = false;
      _handsArmed = res['status'] == 'ARMED';
      _handsOutput = _handsArmed
          ? 'ARMED. Test taps/text stay on this screen; banking apps refused.'
          : 'Disarmed. (${res['status']})';
    });
  }

  String _handsResult(Map<String, dynamic> res) {
    final status = res['status'] ?? 'ERROR';
    final err = res['errorMessage'];
    return err == null || (err as String).isEmpty
        ? 'status=$status success=${res['success']}'
        : 'status=$status success=${res['success']} msg=$err';
  }

  Future<void> _handsTap() async {
    setState(() {
      _handsBusy = true;
      _handsOutput = 'Tapping...';
    });
    // Lands on this test screen while it is open (Friday app, not banking).
    final res = await _hands.tap(0.5, 0.5);
    if (!mounted) return;
    setState(() {
      _handsBusy = false;
      _handsOutput = _handsResult(res);
    });
  }

  Future<void> _handsEnterText() async {
    setState(() {
      _handsBusy = true;
      _handsOutput = 'Setting text...';
    });
    final res = await _hands.enterText('Friday123');
    if (!mounted) return;
    setState(() {
      _handsBusy = false;
      _handsOutput = _handsResult(res);
    });
  }

  Future<void> _runAgent() async {
    final goal = _goalField.text.trim();
    if (goal.isEmpty || _agentBusy) return;
    setState(() {
      _agentBusy = true;
      _agentOutput = 'Running: $goal';
    });
    final agent = FridayAgent(
      eyes: EyesAdapter(_eyes),
      hands: HandsAdapter(_hands),
      model: BrainAdapter(_brain),
    );
    try {
      final result = await agent.runGoal(
        goal,
        maxSteps: 5,
        onLog: (line) {
          if (!mounted) return;
          setState(() {
            _agentOutput = '$_agentOutput\n$line';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _agentBusy = false;
        _agentOutput =
            '$_agentOutput\nFinished: ${result.status} — ${result.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _agentBusy = false;
        _agentOutput = '$_agentOutput\nERROR: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: const Text('Friday manual test'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Manual only. No auto capture, no background actions. '
            'Accessibility trees may miss some pixels/views (no MediaProjection yet).',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFF1E1E1E),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('1. Eyes — screen summary',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _eyesBusy ? null : _checkEnabled,
                        child: const Text('Check enabled'),
                      ),
                      OutlinedButton(
                        onPressed: () => _eyes.openAccessibilitySettings(),
                        child: const Text('Open settings'),
                      ),
                      ElevatedButton(
                        onPressed: _eyesBusy ? null : _getSummary,
                        child: const Text('Get summary'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _eyesOutput,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFF1E1E1E),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('2. Brain — local GGUF (135M, on-device)',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text(
                      'llama_flutter_android 0.2.6. No cloud API, no key. Verbatim output; no fake replies.',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _brainBusy ? null : _brainFind,
                        child: const Text('Find model'),
                      ),
                      ElevatedButton(
                        onPressed: _brainBusy ? null : _brainDownload,
                        child: const Text('Download 135M'),
                      ),
                      ElevatedButton(
                        onPressed:
                            (_brainBusy || _brainModelPath == null) ? null : _brainLoad,
                        child: const Text('Load 135M'),
                      ),
                      ElevatedButton(
                        onPressed:
                            (_brainBusy || !_brain.isReady) ? null : _brainInfer,
                        child: const Text('Infer "Say ok"'),
                      ),
                      ElevatedButton(
                        onPressed: (_brainBusy || !_brain.isReady)
                            ? null
                            : _brainInferCommand,
                        child: const Text('Infer "open youtube"'),
                      ),
                      ElevatedButton(
                        onPressed: (_brainBusy || !_brain.isReady)
                            ? null
                            : _brainInferAgentAction,
                        child: const Text('Infer UI Action'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _brainOutput,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFF1E1E1E),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('3. Hands — tap + text (armed-only)',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text(
                      'Arm first. Refuses banking/payment apps. Test stays on this screen.',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _handsField,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Hands text target',
                      hintStyle: TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _handsBusy ? null : _handsToggleArm,
                        child: Text(_handsArmed ? 'Disarm' : 'Arm'),
                      ),
                      ElevatedButton(
                        onPressed:
                            (_handsBusy || !_handsArmed) ? null : _handsTap,
                        child: const Text('Tap center'),
                      ),
                      ElevatedButton(
                        onPressed: (_handsBusy || !_handsArmed)
                            ? null
                            : _handsEnterText,
                        child: const Text('Enter "Friday123"'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _handsOutput,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFF1E1E1E),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('4. Agent loop — goal in, max 5 steps',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text(
                      'Needs 135M loaded + Hands armed. Stops on DONE, disarm, banking app, or 5 steps.',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _goalField,
                    enabled: !_agentBusy,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Goal, e.g. tap the search button',
                      hintStyle: TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: (_agentBusy ||
                            !_brain.isReady ||
                            !_handsArmed)
                        ? null
                        : _runAgent,
                    child: Text(_agentBusy ? 'Running...' : 'Run goal'),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _agentOutput,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
