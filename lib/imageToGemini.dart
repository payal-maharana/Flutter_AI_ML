///googole gemini analytict with image selection
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
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
//       title: 'Gemini Vision Scanner',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData.dark().copyWith(
//         scaffoldBackgroundColor: Colors.black,
//         colorScheme: const ColorScheme.dark(
//           primary: Colors.tealAccent,
//           secondary: Colors.deepPurpleAccent,
//         ),
//       ),
//       home: GeminiScannerScreen(cameras: cameras),
//     );
//   }
// }

class GeminiScannerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const GeminiScannerScreen({super.key, required this.cameras});

  @override
  State<GeminiScannerScreen> createState() => _GeminiScannerScreenState();
}

class _GeminiScannerScreenState extends State<GeminiScannerScreen> {
  CameraController? _cameraController;
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

  Future<void> _captureAndAnalyze() async {
    if (_processing || _cameraController == null) return;
    setState(() => _processing = true);

    try {
      final picture = await _cameraController!.takePicture();
      final file = File(picture.path);
      await _navigateToAnalysis(file);
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
      await _navigateToAnalysis(File(image.path));
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _navigateToAnalysis(File file) async {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GeminiAnalysisScreen(imageFile: file),
        ),
      );
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
        title: const Text('Gemini Vision Scanner'),
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
                  onTap: _captureAndAnalyze,
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
// GEMINI ANALYSIS SCREEN - NO ML KIT NEEDED
// ============================================================================
class GeminiAnalysisScreen extends StatefulWidget {
  final File imageFile;

  const GeminiAnalysisScreen({super.key, required this.imageFile});

  @override
  State<GeminiAnalysisScreen> createState() => _GeminiAnalysisScreenState();
}

class _GeminiAnalysisScreenState extends State<GeminiAnalysisScreen> {
  String? _analysisResult;
  bool _loading = false;

  //  Replace with your Gemini API Key
  final String _apiKey = 'your Gemini API Key';

  @override
  void initState() {
    super.initState();
    // Automatically analyze on load
    _analyzeImageWithGemini();
  }

  Future<void> _analyzeImageWithGemini() async {
    setState(() {
      _loading = true;
      _analysisResult = null;
    });

    try {
      // Convert image to base64
      final bytes = await widget.imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Detect MIME type
      String mimeType = 'image/jpeg';
      final ext = widget.imageFile.path.split('.').last.toLowerCase();
      if (ext == 'png') {
        mimeType = 'image/png';
      } else if (ext == 'webp') {
        mimeType = 'image/webp';
      } else if (ext == 'gif') {
        mimeType = 'image/gif';
      }

      final prompt = '''
You are an expert data extraction and analysis AI.

Analyze this image thoroughly and extract ALL information present. Follow these steps:

1. **Document Type Identification**
   - Identify what type of document/card/image this is (e.g., ID card, business card, receipt, invoice, form, certificate, product label, menu, ticket, etc.)

2. **Complete Text Extraction**
   - Extract ALL visible text from the image
   - Maintain the structure and hierarchy
   - Include headers, labels, values, fine print, etc.
   - Read text in any orientation or angle

3. **Data Structuring**
   - Organize extracted data into logical categories
   - Create clear key-value pairs
   - Identify important fields (names, dates, numbers, amounts, etc.)

4. **Analysis & Insights**
   - Summarize the key information
   - Highlight important dates, amounts, or identifiers
   - Note any patterns or relationships in the data

5. **Output Format**
   - Provide a well-structured professional & readable format with all extracted data
   - Include a "document_type" field
   - Include an "extracted_fields" object with all key-value pairs
   - Include a "summary" field explaining what this document contains
   - Include a "raw_text" field with all visible text

don't give json data, give only Necessary data in key-value format.

Please analyze this image now and provide comprehensive results.
''';

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
                {
                  "inline_data": {"mime_type": mimeType, "data": base64Image},
                },
              ],
            },
          ],
          "generationConfig": {
            "temperature": 0.4,
            "topK": 32,
            "topP": 1,
            "maxOutputTokens": 4096,
          },
        }),
      );

      print("Gemini Response Status: ${response.statusCode}");
      print("Gemini Response Body: ${response.body}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        String? aiText =
            data['candidates']?[0]?['content']?['parts']?[0]?['text'];

        setState(() {
          _analysisResult = aiText?.trim().isNotEmpty == true
              ? aiText!.trim()
              : 'No data could be extracted from this image.';
        });
      } else {
        setState(() {
          _analysisResult =
              'API Error: ${response.statusCode}\n${response.reasonPhrase}\n\n${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _analysisResult = 'Error analyzing image: $e';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemini Analysis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.tealAccent),
            onPressed: _loading ? null : _analyzeImageWithGemini,
            tooltip: 'Analyze Again',
          ),
          if (_analysisResult != null)
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.tealAccent),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _analysisResult!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Analysis copied to clipboard!'),
                  ),
                );
              },
              tooltip: 'Copy Results',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Preview
            Text(
              'Image:',
              style: TextStyle(
                color: Colors.tealAccent[200],
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Image.file(
                widget.imageFile,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),

            const SizedBox(height: 30),

            // Analysis Results
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: Colors.deepPurpleAccent[100],
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Gemini AI Analysis:',
                  style: TextStyle(
                    color: Colors.deepPurpleAccent[100],
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_loading)
              Center(
                child: Column(
                  children: const [
                    SizedBox(height: 40),
                    CircularProgressIndicator(color: Colors.tealAccent),
                    SizedBox(height: 16),
                    Text(
                      'Analyzing image with Gemini AI...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              )
            else if (_analysisResult != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.deepPurpleAccent.withOpacity(0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurpleAccent.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: SelectableText(
                  _analysisResult!,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    height: 1.6,
                    letterSpacing: 0.2,
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Info Card
            if (!_loading && _analysisResult != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: const [
                    Icon(
                      Icons.info_outline,
                      color: Colors.tealAccent,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Powered by Gemini 2.0 Flash Vision',
                        style: TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
