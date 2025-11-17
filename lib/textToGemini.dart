///firstly in text then filter with gemini
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   final cameras = await availableCameras();
//   runApp(MyApp(cameras: cameras));
// }
//
// class MyApp extends StatelessWidget {
//   final List<CameraDescription> cameras;
//   const MyApp({super.key, required this.cameras});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'AI Text Scanner',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData.dark().copyWith(
//         scaffoldBackgroundColor: Colors.black,
//         colorScheme: const ColorScheme.dark(
//           primary: Colors.tealAccent,
//           secondary: Colors.deepPurpleAccent,
//         ),
//       ),
//       home: MLTextScannerScreen1(cameras: cameras),
//     );
//   }
// }

class MLTextScannerScreen1 extends StatefulWidget {
  final List<CameraDescription> cameras;
  const MLTextScannerScreen1({super.key, required this.cameras});

  @override
  State<MLTextScannerScreen1> createState() => _MLTextScannerScreen1State();
}

class _MLTextScannerScreen1State extends State<MLTextScannerScreen1> {
  CameraController? _cameraController;
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final ImagePicker _picker = ImagePicker();
  bool _processing = false;

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

  Future<void> _pickFromGallery() async {
    try {
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      await _processImage(File(image.path));
    } catch (e) {
      _showError(e);
    }
  }

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

  void _showError(Object e) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Error: $e')));
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close();
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
      appBar: AppBar(title: const Text('AI Smart Scanner'), centerTitle: true),
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
              ],
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
            width: 80,
            height: 80,
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
            child: Icon(icon, color: color, size: 36),
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
Your task is to deeply analyze the given raw data and perform the following steps in sequence:

Understand the Context

Identify what kind of information the raw data represents (e.g., profile, transaction, booking, product, consultation, review, etc.).

Clearly state what type of data or card it belongs to (e.g., “Artist Profile Card”, “Booking Details Card”, “Payment History Card”, etc.).

Extract the Necessary Data

Parse and extract only useful, relevant, and meaningful information.

Ignore any noise, filler text, or redundant details.

Use your reasoning to infer missing but logically implied data if clearly supported by the context.

Analyze and Summarize

Briefly explain the purpose or meaning of the data.

Identify relationships or patterns if present.

If numerical or categorical data is included, analyze trends, counts, or significant insights.

Output Format (Structured and Clean)

Present the final extracted information in a clean professional & readable or key-value format, with concise and meaningful field names.

Follow it with a short summary paragraph that explains what the data means and what type of card it is.

don't give json data, give only Necessary data in key-value format.
OCR Text:
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
      print("dddddddddddddddddddddddddddddddddd${response.body}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        String? aiText;
        try {
          aiText = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        } catch (_) {}
        if (aiText == null) {
          try {
            aiText = data['candidates']?[0]?['output'];
          } catch (_) {}
        }

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
      setState(() {
        _filteredData = 'Error: $e';
      });
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
