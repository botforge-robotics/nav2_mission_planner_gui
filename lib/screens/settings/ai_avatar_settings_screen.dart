import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';

class AiAvatarSettingsScreen extends StatefulWidget {
  const AiAvatarSettingsScreen({super.key});

  @override
  State<AiAvatarSettingsScreen> createState() => _AiAvatarSettingsScreenState();
}

class _AiAvatarSettingsScreenState extends State<AiAvatarSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _testingKey = false;
  String? _testResult;
  bool _testSuccess = false;

  late final TextEditingController _apiKeyController;
  late final TextEditingController _systemPromptController;

  String _selectedModel = 'gemini-2.0-flash-exp';
  String _selectedVoice = 'Aoede';
  String _selectedScenario = 'real_estate'; // 'real_estate', 'shopping_mall', 'custom'
  double _speedLimit = 0.35;
  int _silenceTimeout = 8;
  bool _obscureApiKey = true;

  Map<String, String> _waypointsKnowledge = {};

  final List<String> _models = [
    'gemini-2.0-flash-exp',
    'gemini-2.0-flash',
  ];

  final List<Map<String, String>> _voices = [
    {'id': 'Aoede', 'name': 'Aoede (Warm & Natural)', 'desc': 'Friendly docent tone'},
    {'id': 'Kore', 'name': 'Kore (Relaxed & Conversational)', 'desc': 'Welcoming host voice'},
    {'id': 'Puck', 'name': 'Puck (Playful & Energetic)', 'desc': 'Engaging mall guide'},
    {'id': 'Charon', 'name': 'Charon (Deep & Professional)', 'desc': 'Authoritative concierge'},
    {'id': 'Fenrir', 'name': 'Fenrir (Confident & Direct)', 'desc': 'Clear executive tone'},
  ];

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _systemPromptController = TextEditingController();
    _loadFromRobot();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  String _getRobotIp() {
    final robot = context.read<ConnectionProvider>().robot;
    return robot?.ip ?? '127.0.0.1';
  }

  Future<void> _loadFromRobot() async {
    setState(() => _loading = true);
    try {
      final api = SdkApiService(_getRobotIp());
      final config = await api.fetchAiAvatarConfig();

      if (!mounted) return;
      setState(() {
        _apiKeyController.text = (config['apiKey'] ?? '').toString();
        _selectedModel = (config['model'] ?? 'gemini-2.0-flash-exp').toString();
        _selectedVoice = (config['voice'] ?? 'Aoede').toString();
        _selectedScenario = (config['scenario'] ?? 'real_estate').toString();
        _speedLimit = (config['speedLimitMps'] as num?)?.toDouble() ?? 0.35;
        _silenceTimeout = (config['silenceTimeoutSec'] as num?)?.toInt() ?? 8;
        _systemPromptController.text = (config['systemInstruction'] ?? '').toString();

        final wp = config['waypointsKnowledge'];
        if (wp is Map) {
          _waypointsKnowledge = wp.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load settings from robot SDK: $e')),
      );
    }
  }

  void _applyScenarioPreset(String scenario) {
    setState(() {
      _selectedScenario = scenario;
      if (scenario == 'real_estate') {
        _systemPromptController.text =
            "You are NavPro Assistant, an autonomous interactive robot guide for this luxury model apartment. "
            "You speak warmly, concisely, and naturally as if having an in-person conversation. "
            "When visitors ask to see a room or go somewhere, use your navigate_to_place tool to escort them. "
            "When they ask for specs, floor plans, or photos, use show_media. "
            "Always be welcoming and helpful.";
        _waypointsKnowledge = {
          "kitchen": "14x11 ft modular kitchen with Italian quartz countertops, soft-close Blum hardware, and integrated induction hob.",
          "master_bedroom": "16x14 ft master bedroom with solid hardwood flooring, attached walk-in wardrobe, and south-facing view.",
          "living_room": "Spacious 20x15 ft living hall with double-glazed French windows, 10-ft ceiling, and smart ambient lighting.",
          "balcony": "East-facing sunrise balcony with anti-skid vitrified tiles and glass balustrades.",
          "foyer": "Main entrance foyer with biometric smart lock and shoe console."
        };
      } else if (scenario == 'shopping_mall') {
        _systemPromptController.text =
            "You are NavPro Concierge, an autonomous helpful assistant in this modern shopping mall. "
            "You help shoppers find stores, restrooms, and amenities. "
            "When a shopper asks to be guided or taken to a store, use your navigate_to_place tool to escort them. "
            "Announce active promotions and food court options when asked.";
        _waypointsKnowledge = {
          "apple_store": "Ground Floor central atrium, specializing in iPhones, MacBooks, and Apple repairs.",
          "starbucks": "Ground Floor East entrance, coffee, pastries, and seating.",
          "food_court": "Level 3 with multi-cuisine dining options and family seating.",
          "restrooms": "Ground Floor Corridor B, next to elevator bank."
        };
      } else if (scenario == 'educational_amr') {
        _systemPromptController.text =
            "You are the AI Voice Assistant for this robotics laboratory and STEM educational workshop. "
            "You are an inspiring, friendly, and knowledgeable robotics mentor. "
            "You explain robotics concepts (such as autonomous mobile robots, robotic arms and kinematics, LiDAR scanning, SLAM mapping, ROS 2 navigation, path planning, and autonomous dispatch) in an engaging, easy-to-understand way for students and visitors. "
            "When asked for demonstrations or lab workstation visits, use your navigate_to_place tool to escort them. "
            "When asked for diagrams, schematics, or code examples, use show_media.";
        _waypointsKnowledge = {
          "station_1_assembly": "Hardware assembly, motor drivers, and robotic arm test bench.",
          "station_2_lidar": "Sensors, camera vision, and 2D LiDAR scanning calibration zone.",
          "station_3_programming": "Software workstation for ROS 2 nodes, Python SDK, and Mission Planner.",
          "arena": "Main autonomous testing arena and obstacle avoidance course.",
          "dock": "Auto-docking station."
        };
      }
    });
  }

  Future<void> _testApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _testResult = 'Please enter an API Key first.';
        _testSuccess = false;
      });
      return;
    }

    setState(() {
      _testingKey = true;
      _testResult = null;
    });

    try {
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models?key=$key');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        setState(() {
          _testSuccess = true;
          _testResult = 'Connection verified! Google Gemini API key is valid.';
        });
      } else {
        setState(() {
          _testSuccess = false;
          _testResult = 'Google API error (${resp.statusCode}): ${resp.body}';
        });
      }
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = 'Connection failed: $e';
      });
    } finally {
      if (mounted) setState(() => _testingKey = false);
    }
  }

  Future<void> _saveToRobot() async {
    setState(() => _saving = true);
    try {
      final payload = {
        'enabled': true,
        'apiKey': _apiKeyController.text.trim(),
        'model': _selectedModel,
        'voice': _selectedVoice,
        'scenario': _selectedScenario,
        'speedLimitMps': _speedLimit,
        'silenceTimeoutSec': _silenceTimeout,
        'systemInstruction': _systemPromptController.text.trim(),
        'waypointsKnowledge': _waypointsKnowledge,
      };

      final api = SdkApiService(_getRobotIp());
      await api.updateAiAvatarConfig(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI Avatar configuration deployed & saved to robot!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to deploy to robot: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Voice Assistant'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _saveToRobot,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_rounded),
            label: const Text('Apply to Assistant'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isDesktop ? 860 : 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Hero Info Card
                        Card(
                          color: colors.primary.withValues(alpha: 0.1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                            side: BorderSide(color: colors.primary.withValues(alpha: 0.4)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: colors.primary,
                                  child: const Icon(Icons.record_voice_over_rounded, color: Colors.white),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Onboard AI Voice Assistant',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Interactive voice conversation • Natural dialogue • Seamless guided assistance',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: colors.textSecondary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Section 1: API Key & Model
                        Text('1. Voice Intelligence Engine',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: AppSpacing.sm),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _apiKeyController,
                                  obscureText: _obscureApiKey,
                                  decoration: InputDecoration(
                                    labelText: 'Gemini API Key',
                                    hintText: 'AIzaSy...',
                                    prefixIcon: const Icon(Icons.key_rounded),
                                    suffixIcon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(_obscureApiKey ? Icons.visibility : Icons.visibility_off),
                                          onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                                        ),
                                        TextButton(
                                          onPressed: _testingKey ? null : _testApiKey,
                                          child: _testingKey
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Text('Test'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_testResult != null) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  Row(
                                    children: [
                                      Icon(
                                        _testSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
                                        size: 18,
                                        color: _testSuccess ? Colors.green : Colors.red,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _testResult!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _testSuccess ? Colors.green : Colors.red,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.md),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _selectedModel,
                                        decoration: const InputDecoration(
                                          labelText: 'Voice Intelligence Model',
                                          prefixIcon: Icon(Icons.bolt_rounded),
                                        ),
                                        items: _models
                                            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                                            .toList(),
                                        onChanged: (v) {
                                          if (v != null) setState(() => _selectedModel = v);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _selectedVoice,
                                        decoration: const InputDecoration(
                                          labelText: 'Voice Persona',
                                          prefixIcon: Icon(Icons.record_voice_over_outlined),
                                        ),
                                        items: _voices
                                            .map((v) => DropdownMenuItem(
                                                value: v['id'], child: Text(v['name']!)))
                                            .toList(),
                                        onChanged: (v) {
                                          if (v != null) setState(() => _selectedVoice = v);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Section 2: Scenario Selection
                        Text('2. Commercial Scenario & Application',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: AppSpacing.sm),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'real_estate',
                                      icon: Icon(Icons.home_work_rounded),
                                      label: Text('Real Estate'),
                                    ),
                                    ButtonSegment(
                                      value: 'shopping_mall',
                                      icon: Icon(Icons.storefront_rounded),
                                      label: Text('Shopping Mall'),
                                    ),
                                    ButtonSegment(
                                      value: 'educational_amr',
                                      icon: Icon(Icons.school_rounded),
                                      label: Text('Robotics & Education'),
                                    ),
                                    ButtonSegment(
                                      value: 'custom',
                                      icon: Icon(Icons.tune_rounded),
                                      label: Text('Custom Persona'),
                                    ),
                                  ],
                                  selected: {_selectedScenario},
                                  onSelectionChanged: (val) {
                                    _applyScenarioPreset(val.first);
                                  },
                                ),
                                const SizedBox(height: AppSpacing.md),
                                TextField(
                                  controller: _systemPromptController,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    labelText: 'Assistant System Prompt & Persona',
                                    hintText: 'Enter custom persona prompt...',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Section 3: Safety & Interaction Parameters
                        Text('3. Safety, Speed & Interaction Limits',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: AppSpacing.sm),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Guided Escort Walking Speed'),
                                  subtitle: Text(
                                    '${_speedLimit.toStringAsFixed(2)} m/s (Comfortable pace for following visitors)',
                                  ),
                                  trailing: SizedBox(
                                    width: 180,
                                    child: Slider(
                                      min: 0.20,
                                      max: 0.60,
                                      divisions: 8,
                                      value: _speedLimit,
                                      onChanged: (val) => setState(() => _speedLimit = val),
                                    ),
                                  ),
                                ),
                                const Divider(),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Auto-Silence Watchdog Timeout'),
                                  subtitle: Text(
                                    '$_silenceTimeout seconds (Mutes mic and stops token stream if visitor is silent)',
                                  ),
                                  trailing: SizedBox(
                                    width: 180,
                                    child: Slider(
                                      min: 4,
                                      max: 20,
                                      divisions: 8,
                                      value: _silenceTimeout.toDouble(),
                                      onChanged: (val) => setState(() => _silenceTimeout = val.round()),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Save & Deploy Button
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: colors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                            ),
                          ),
                          onPressed: _saving ? null : _saveToRobot,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.rocket_launch_rounded),
                          label: Text(
                            _saving ? 'Applying Configuration...' : 'Save & Apply to AI Assistant',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
