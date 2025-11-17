import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

enum RecordingState { idle, recording, paused, stopped }

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Summarizer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      themeMode: ThemeMode.system,
      home: const AudioSummaryScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AudioSummaryScreen extends StatefulWidget {
  const AudioSummaryScreen({super.key});

  @override
  State<AudioSummaryScreen> createState() => _AudioSummaryScreenState();
}

class _AudioSummaryScreenState extends State<AudioSummaryScreen> {
  // 🔒 Replace with your actual Gemini API key
  final String _apiKey = "AIzaSyCPv18NEa4eonJe3EcY29Tn852QG_uPxMs";

  // Supported audio formats by Gemini API
  static const Map<String, String> _supportedFormats = {
    'mp3': 'audio/mp3',
    'wav': 'audio/wav',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'flac': 'audio/flac',
    'm4a': 'audio/mp4',
  };

  static const int _maxFileSizeBytes = 100 * 1024 * 1024; // 100MB limit

  String? _summary;
  String? _errorMessage;
  bool _isLoading = false;
  String? _fileName;
  String? _fileSize;

  // Recording state variables
  final AudioRecorder _audioRecorder = AudioRecorder();
  RecordingState _recordingState = RecordingState.idle;
  String? _recordedFilePath;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  bool _hasPermission = false;

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _getMimeType(String extension) {
    return _supportedFormats[extension.toLowerCase()] ?? 'audio/mpeg';
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _pickAndSummarizeAudio() async {
    // Validate API key first
    if (_apiKey == "YOUR_GEMINI_API_KEY_HERE" || _apiKey.isEmpty) {
      setState(() {
        _errorMessage =
            "⚠️ Please add your Gemini API key in the code (line 33)";
      });
      _showSnackBar("API key not configured", isError: true);
      return;
    }

    try {
      // Pick audio file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _supportedFormats.keys.toList(),
        withData: false,
        withReadStream: false,
      );

      if (result == null || result.files.single.path == null) {
        return; // User cancelled
      }

      final pickedFile = result.files.single;
      final filePath = pickedFile.path!;
      final file = File(filePath);

      // Validate file exists
      if (!await file.exists()) {
        setState(() {
          _errorMessage = "❌ File not found. Please try again.";
        });
        return;
      }

      // Validate file size
      final fileSize = await file.length();
      if (fileSize > _maxFileSizeBytes) {
        setState(() {
          _errorMessage =
              "❌ File too large! Maximum size is 100MB.\nYour file: ${_formatFileSize(fileSize)}";
        });
        _showSnackBar("File exceeds 100MB limit", isError: true);
        return;
      }

      // Validate file extension
      final extension = pickedFile.extension?.toLowerCase() ?? '';
      if (!_supportedFormats.containsKey(extension)) {
        setState(() {
          _errorMessage =
              "❌ Unsupported format: .$extension\n\nSupported formats: ${_supportedFormats.keys.join(', ')}";
        });
        _showSnackBar("Unsupported audio format", isError: true);
        return;
      }

      // Start processing
      setState(() {
        _isLoading = true;
        _summary = null;
        _errorMessage = null;
        _fileName = pickedFile.name;
        _fileSize = _formatFileSize(fileSize);
      });

      _showSnackBar("Processing audio... This may take a moment");

      // Initialize Gemini model
      final model = GenerativeModel(model: 'gemini-2.0-flash', apiKey: _apiKey);

      // Read file and create request
      final bytes = await file.readAsBytes();
      final mimeType = _getMimeType(extension);

      final prompt = TextPart(
        "You are an expert executive assistant. Distill this audio into ONLY critical business information.\n\n"
        "STRICT FILTERING RULES:\n"
        "• REMOVE: All greetings, small talk, casual chat, filler words, repetitions, off-topic discussions\n"
        "• KEEP: Only essential facts, decisions, commitments, deadlines, and action items\n"
        "• BE RUTHLESS: Exclude everything that isn't business-critical\n\n"
        "SPEAKER IDENTIFICATION:\n"
        "• Listen carefully and identify speakers by their ACTUAL NAMES if mentioned in the audio\n"
        "• If names are used in conversation, use those exact names\n"
        "• If no names mentioned, use descriptive identifiers like 'Manager', 'Team Lead', 'Client', etc.\n"
        "• Only mention speakers when they contribute important information\n\n"
        "OUTPUT FORMAT (use this exact clean structure):\n\n"
        "CONTEXT\n"
        "One sentence explaining what this meeting/conversation is about.\n\n"
        "KEY POINTS\n"
        "• Name: Their important contribution in one clear sentence\n"
        "• Name: Their important contribution in one clear sentence\n"
        "(Only list genuinely important contributions)\n\n"
        "DECISIONS\n"
        "1. First decision\n"
        "2. Second decision\n"
        "(Skip this section if no decisions were made)\n\n"
        "ACTION ITEMS\n"
        "→ Task description | Owner: Name | Due: Date\n"
        "→ Task description | Owner: Name | Due: Date\n"
        "(Skip this section if no action items)\n\n"
        "IMPORTANT DETAILS\n"
        "List any critical numbers, dates, commitments, or specific facts.\n"
        "(Skip this section if nothing critical)\n\n"
        "RULES:\n"
        "• Maximum 300 words\n"
        "• Use simple, professional language\n"
        "• Every word must add value\n"
        "• Focus on WHAT was decided, not HOW discussed\n"
        "• Skip empty sections completely\n"
        "• State only clear facts",
      );

      final audioPart = DataPart(mimeType, bytes);

      final content = [
        Content.multi([prompt, audioPart]),
      ];

      final response = await model.generateContent(content);

      if (!mounted) return;

      final summaryText = response.text;

      if (summaryText == null || summaryText.trim().isEmpty) {
        throw Exception("Gemini returned an empty response");
      }

      setState(() {
        _summary = summaryText;
        _errorMessage = null;
      });

      _showSnackBar("✓ Summary generated successfully!");
    } catch (e) {
      if (!mounted) return;

      String errorMsg = "❌ Error: ";
      if (e.toString().contains("API_KEY_INVALID")) {
        errorMsg += "Invalid API key. Please check your Gemini API key.";
      } else if (e.toString().contains("quota")) {
        errorMsg += "API quota exceeded. Please check your Gemini API usage.";
      } else if (e.toString().contains("network") ||
          e.toString().contains("SocketException")) {
        errorMsg += "Network error. Please check your internet connection.";
      } else {
        errorMsg += e.toString();
      }

      setState(() {
        _summary = null;
        _errorMessage = errorMsg;
      });

      _showSnackBar("Failed to generate summary", isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ========== RECORDING METHODS ==========

  String _formatRecordingTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _checkMicrophonePermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      setState(() => _hasPermission = true);
    } else {
      final result = await Permission.microphone.request();
      setState(() => _hasPermission = result.isGranted);
      if (!result.isGranted) {
        _showSnackBar("Microphone permission is required to record audio", isError: true);
      }
    }
  }

  Future<void> _startRecording() async {
    await _checkMicrophonePermission();
    if (!_hasPermission) return;

    try {
      // Create temporary file path
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Check if recorder has permission
      if (await _audioRecorder.hasPermission()) {
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            sampleRate: 44100,
            bitRate: 128000,
          ),
          path: filePath,
        );

        setState(() {
          _recordingState = RecordingState.recording;
          _recordedFilePath = filePath;
          _recordingSeconds = 0;
          _summary = null;
          _errorMessage = null;
          _fileName = null;
          _fileSize = null;
        });

        // Start timer
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() => _recordingSeconds++);
        });

        _showSnackBar("🎤 Recording started");
      }
    } catch (e) {
      _showSnackBar("Failed to start recording: ${e.toString()}", isError: true);
    }
  }

  Future<void> _pauseRecording() async {
    try {
      await _audioRecorder.pause();
      _recordingTimer?.cancel();
      setState(() => _recordingState = RecordingState.paused);
      _showSnackBar("⏸ Recording paused");
    } catch (e) {
      _showSnackBar("Failed to pause recording", isError: true);
    }
  }

  Future<void> _resumeRecording() async {
    try {
      await _audioRecorder.resume();
      setState(() => _recordingState = RecordingState.recording);
      
      // Resume timer
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _recordingSeconds++);
      });

      _showSnackBar("▶ Recording resumed");
    } catch (e) {
      _showSnackBar("Failed to resume recording", isError: true);
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      _recordingTimer?.cancel();
      
      setState(() {
        _recordingState = RecordingState.stopped;
        _recordedFilePath = path;
      });

      if (path != null) {
        _showSnackBar("✓ Recording stopped. Processing...");
        await _processRecordedAudio(path);
      }
    } catch (e) {
      _showSnackBar("Failed to stop recording", isError: true);
    }
  }

  Future<void> _processRecordedAudio(String filePath) async {
    try {
      final file = File(filePath);
      
      if (!await file.exists()) {
        throw Exception("Recorded file not found");
      }

      final fileSize = await file.length();
      
      setState(() {
        _isLoading = true;
        _fileName = "recorded_audio.m4a";
        _fileSize = _formatFileSize(fileSize);
      });

      // Initialize Gemini model
      final model = GenerativeModel(model: 'gemini-2.0-flash', apiKey: _apiKey);

      // Read file and create request
      final bytes = await file.readAsBytes();
      const mimeType = 'audio/mp4'; // M4A uses audio/mp4 MIME type

      final prompt = TextPart(
        "You are an expert executive assistant. Distill this audio into ONLY critical business information.\n\n"
        "STRICT FILTERING RULES:\n"
        "• REMOVE: All greetings, small talk, casual chat, filler words, repetitions, off-topic discussions\n"
        "• KEEP: Only essential facts, decisions, commitments, deadlines, and action items\n"
        "• BE RUTHLESS: Exclude everything that isn't business-critical\n\n"
        "SPEAKER IDENTIFICATION:\n"
        "• Listen carefully and identify speakers by their ACTUAL NAMES if mentioned in the audio\n"
        "• If names are used in conversation, use those exact names\n"
        "• If no names mentioned, use descriptive identifiers like 'Manager', 'Team Lead', 'Client', etc.\n"
        "• Only mention speakers when they contribute important information\n\n"
        "OUTPUT FORMAT (use this exact clean structure):\n\n"
        "CONTEXT\n"
        "One sentence explaining what this meeting/conversation is about.\n\n"
        "KEY POINTS\n"
        "• Name: Their important contribution in one clear sentence\n"
        "• Name: Their important contribution in one clear sentence\n"
        "(Only list genuinely important contributions)\n\n"
        "DECISIONS\n"
        "1. First decision\n"
        "2. Second decision\n"
        "(Skip this section if no decisions were made)\n\n"
        "ACTION ITEMS\n"
        "→ Task description | Owner: Name | Due: Date\n"
        "→ Task description | Owner: Name | Due: Date\n"
        "(Skip this section if no action items)\n\n"
        "IMPORTANT DETAILS\n"
        "List any critical numbers, dates, commitments, or specific facts.\n"
        "(Skip this section if nothing critical)\n\n"
        "RULES:\n"
        "• Maximum 300 words\n"
        "• Use simple, professional language\n"
        "• Every word must add value\n"
        "• Focus on WHAT was decided, not HOW discussed\n"
        "• Skip empty sections completely\n"
        "• State only clear facts",
      );

      final audioPart = DataPart(mimeType, bytes);

      final content = [
        Content.multi([prompt, audioPart]),
      ];

      final response = await model.generateContent(content);

      if (!mounted) return;

      final summaryText = response.text;

      if (summaryText == null || summaryText.trim().isEmpty) {
        throw Exception("Gemini returned an empty response");
      }

      setState(() {
        _summary = summaryText;
        _errorMessage = null;
        _recordingState = RecordingState.idle;
        _recordingSeconds = 0;
      });

      _showSnackBar("✓ Summary generated successfully!");

      // Clean up temporary file
      try {
        await file.delete();
      } catch (e) {
        // Ignore cleanup errors
      }
    } catch (e) {
      if (!mounted) return;

      String errorMsg = "❌ Error: ";
      if (e.toString().contains("API_KEY_INVALID")) {
        errorMsg += "Invalid API key. Please check your Gemini API key.";
      } else if (e.toString().contains("quota")) {
        errorMsg += "API quota exceeded. Please check your Gemini API usage.";
      } else if (e.toString().contains("network") ||
          e.toString().contains("SocketException")) {
        errorMsg += "Network error. Please check your internet connection.";
      } else {
        errorMsg += e.toString();
      }

      setState(() {
        _summary = null;
        _errorMessage = errorMsg;
        _recordingState = RecordingState.idle;
      });

      _showSnackBar("Failed to generate summary", isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Modern Header with gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF1E3A8A), const Color(0xFF3B82F6)]
                      : [const Color(0xFF2563EB), const Color(0xFF3B82F6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.mic_none_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Audio Summarizer",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "AI-Powered Meeting Intelligence",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Main Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Upload Section
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.cloud_upload_outlined,
                              size: 40,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "Upload Your Audio File",
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "MP3, WAV, AAC, OGG, FLAC, M4A • Max 100MB",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 56,
                            child: FilledButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : _pickAndSummarizeAudio,
                              icon: Icon(
                                _isLoading
                                    ? Icons.hourglass_empty
                                    : Icons.file_upload_outlined,
                              ),
                              label: Text(
                                _isLoading
                                    ? "Processing..."
                                    : "Select Audio File",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Recording Section
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50.withOpacity(0.7),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.mic_rounded,
                              size: 40,
                              color: _recordingState == RecordingState.recording
                                  ? Colors.red
                                  : theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "Record Audio",
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _recordingState == RecordingState.idle
                                ? "Record live conversation • Unlimited duration"
                                : "Recording: ${_formatRecordingTime(_recordingSeconds)}",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _recordingState == RecordingState.recording
                                  ? Colors.red
                                  : Colors.grey,
                              fontWeight: _recordingState != RecordingState.idle
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: _recordingState != RecordingState.idle
                                  ? 16
                                  : 13,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Recording Controls
                          if (_recordingState == RecordingState.idle)
                            SizedBox(
                              height: 56,
                              child: FilledButton.icon(
                                onPressed: _isLoading ? null : _startRecording,
                                icon: const Icon(Icons.fiber_manual_record),
                                label: const Text(
                                  "Start Recording",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            )
                          else
                            Row(
                              children: [
                                // Pause/Resume Button
                                Expanded(
                                  child: SizedBox(
                                    height: 56,
                                    child: FilledButton.icon(
                                      onPressed: _recordingState ==
                                              RecordingState.recording
                                          ? _pauseRecording
                                          : _resumeRecording,
                                      icon: Icon(
                                        _recordingState ==
                                                RecordingState.recording
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                      ),
                                      label: Text(
                                        _recordingState ==
                                                RecordingState.recording
                                            ? "Pause"
                                            : "Resume",
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _recordingState ==
                                                RecordingState.recording
                                            ? Colors.orange
                                            : Colors.green,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Stop Button
                                Expanded(
                                  child: SizedBox(
                                    height: 56,
                                    child: FilledButton.icon(
                                      onPressed: _stopRecording,
                                      icon: const Icon(Icons.stop),
                                      label: const Text(
                                        "Stop",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.red.shade700,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // File Info Card
                    if (_fileName != null && _fileSize != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.audio_file,
                                color: Colors.green,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _fileName!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _fileSize!,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_isLoading)
                              const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            else
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 28,
                              ),
                          ],
                        ),
                      ),

                    if (_fileName != null && _fileSize != null)
                      const SizedBox(height: 24),

                    // Loading State
                    if (_isLoading)
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              width: 60,
                              height: 60,
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              "Analyzing Audio...",
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Gemini AI is processing your audio\nThis may take 10-30 seconds",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Error Display
                    if (_errorMessage != null && !_isLoading)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.red.shade200,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: Colors.red.shade700,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  "Error Occurred",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.red.shade900,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Summary Display
                    if (_summary != null && !_isLoading)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.description_outlined,
                                    color: Colors.green.shade700,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  "Meeting Summary",
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 32),
                            SelectableText(
                              _summary!,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.8,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
