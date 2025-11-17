import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:file_picker/file_picker.dart';
import 'package:test_ml/speechUpload.dart';
import 'package:test_ml/textToGemini.dart';

import 'imageToGemini.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Text & Audio Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.tealAccent,
          secondary: Colors.deepPurpleAccent,
        ),
      ),
      home: MainNavigation(cameras: cameras),
    );
  }
}

class MainNavigation extends StatefulWidget {
  final List<CameraDescription> cameras;
  const MainNavigation({super.key, required this.cameras});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> _screens = [
      MLTextScannerScreen(cameras: widget.cameras),
      MLTextScannerScreen1(cameras: widget.cameras),
      GeminiScannerScreen(cameras: widget.cameras),
      AudioSummaryScreen(),
    ];

    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: Colors.black,
        selectedItemColor: Colors.tealAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.audiotrack), label: 'Voice'),
          BottomNavigationBarItem(icon: Icon(Icons.text_format), label: 'Text'),
          BottomNavigationBarItem(
            icon: Icon(Icons.image_search_rounded),
            label: 'Gemini',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.upload), label: 'Upload'),
        ],
      ),
    );
  }
}

class MLTextScannerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const MLTextScannerScreen({super.key, required this.cameras});

  @override
  State<MLTextScannerScreen> createState() => _MLTextScannerScreenState();
}

class _MLTextScannerScreenState extends State<MLTextScannerScreen> {
  CameraController? _cameraController;
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final ImagePicker _picker = ImagePicker();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _processing = false;
  bool _isListening = false;
  String _speechText = '';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    await Permission.camera.request();
    final camera = widget.cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    _cameraController = CameraController(camera, ResolutionPreset.high);
    await _cameraController!.initialize();
    if (mounted) setState(() {});
  }

  // Capture image and recognize text
  Future<void> _captureAndRecognize() async {
    if (_processing || _cameraController == null) return;
    setState(() => _processing = true);

    try {
      final picture = await _cameraController!.takePicture();
      final file = File(picture.path);
      await _processImage(file);
    } catch (e) {
      _showError(e);
    } finally {
      setState(() => _processing = false);
    }
  }

  // Pick image from gallery
  Future<void> _pickFromGallery() async {
    try {
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      await _processImage(File(image.path));
    } catch (e) {
      _showError(e);
    }
  }

  // Recognize text from image
  Future<void> _processImage(File file) async {
    setState(() => _processing = true);
    try {
      final inputImage = InputImage.fromFile(file);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RecognizedTextScreen(text: recognizedText.text),
          ),
        );
      }
    } catch (e) {
      _showError(e);
    } finally {
      setState(() => _processing = false);
    }
  }

  //  Record and transcribe speech
  Future<void> _recordAndTranscribe() async {
    var micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _showSnackBar(' Microphone permission not granted');
      return;
    }

    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          debugPrint('Speech status: $status');

          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);

            if (_speechText.trim().isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RecognizedTextScreen(text: _speechText),
                ),
              );
            } else {
              // _showSnackBar("😕 No speech recognized, please try again!");
            }
          }
        },
        onError: (error) {
          debugPrint('Speech error: ${error.errorMsg}');
          _showSnackBar("Sorry, couldn’t recognize your speech! 😕");
          setState(() => _isListening = false);
        },
      );

      if (available) {
        setState(() {
          _isListening = true;
          _speechText = '';
        });

        await _speech.listen(
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 5),
          localeId: 'en_US',
          onResult: (result) {
            setState(() {
              _speechText = result.recognizedWords;
            });
          },
        );
      } else {
        _showSnackBar("⚠️ Speech recognition not available on this device");
      }
    } else {
      setState(() => _isListening = false);
      await _speech.stop();

      if (_speechText.trim().isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RecognizedTextScreen(text: _speechText),
          ),
        );
      } else {
        _showSnackBar("😕 No speech recognized, please try again!");
      }
    }
  }

  Future<void> _pickAudioFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio file selected: ${file.path}')),
        );
        // Future enhancement: send this file to Google Speech-to-Text API
      }
    } catch (e) {
      _showError('Audio selection failed: $e');
    }
  }

  void _showError(Object e) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Error: $e')));
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.tealAccent),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Text & Audio Scanner'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          CameraPreview(_cameraController!),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  color: Colors.deepPurpleAccent,
                  onTap: _pickFromGallery,
                ),
                _buildActionButton(
                  icon: Icons.camera_alt_rounded,
                  label: 'Capture',
                  color: Colors.tealAccent,
                  onTap: _captureAndRecognize,
                ),
                _buildActionButton(
                  icon: _isListening
                      ? Icons.stop_circle_outlined
                      : Icons.mic_rounded,
                  label: _isListening ? 'Stop' : 'Audio',
                  color: Colors.orangeAccent,
                  onTap: _recordAndTranscribe,
                ),
                // _buildActionButton(
                //   icon: Icons.audiotrack_rounded,
                //   label: 'Upload',
                //   color: Colors.blueAccent,
                //   onTap: _pickAudioFile,
                // ),
              ],
            ),
          ),

          //  Add this new section OUTSIDE the button bar
          if (_isListening || _speechText.isNotEmpty)
            Align(
              alignment: Alignment.center,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _speechText.isEmpty ? '🎤 Listening...' : _speechText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _processing ? null : onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// RESULT SCREEN WITH GEMINI INTEGRATION
// ============================================================================
class RecognizedTextScreen extends StatefulWidget {
  final String text;
  const RecognizedTextScreen({super.key, required this.text});

  @override
  State<RecognizedTextScreen> createState() => _RecognizedTextScreenState();
}

class _RecognizedTextScreenState extends State<RecognizedTextScreen> {
  String? _filteredData;
  bool _loading = false;

  // 🔑 Replace with your Gemini API Key
  final String _apiKey = 'your Gemini API Key';

  Future<void> _filterDataWithGemini() async {
    setState(() {
      _loading = true;
      _filteredData = null;
    });

    final prompt =
        '''
You are a data analysis and structuring expert.
Analyze the raw data below, extract structured insights, and summarize it clearly.

OCR or Speech Text:
${widget.text}
''';

    try {
      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=$_apiKey',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": prompt},
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        String? aiText;
        try {
          aiText = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        } catch (_) {}
        setState(() {
          _filteredData = aiText?.trim().isNotEmpty == true
              ? aiText!.trim()
              : 'No structured data returned.';
        });
      } else {
        setState(() {
          _filteredData =
              'Error: ${response.statusCode} - ${response.reasonPhrase}\n${response.body}';
        });
      }
    } catch (e) {
      setState(() => _filteredData = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Extracted Text'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.tealAccent),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard!')),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Raw Extracted Text:',
                style: TextStyle(
                  color: Colors.tealAccent[200],
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.text,
                  style: const TextStyle(fontSize: 15, color: Colors.white70),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _filterDataWithGemini,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Show Filtered Details'),
                ),
              ),
              const SizedBox(height: 25),
              if (_loading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.tealAccent),
                )
              else if (_filteredData != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Filtered Details:',
                      style: TextStyle(
                        color: Colors.deepPurpleAccent[100],
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _filteredData!,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
