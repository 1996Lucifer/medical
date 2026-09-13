import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../network/api_routes.dart';
import '../network/network_manager.dart';

class UploadReportScreen extends StatefulWidget {
  final int patientId;
  const UploadReportScreen({super.key, required this.patientId});

  @override
  State<UploadReportScreen> createState() => _UploadReportScreenState();
}

class _UploadReportScreenState extends State<UploadReportScreen> {
  bool _isUploading = false;
  String _statusMessage = "";

  Future<void> _pickAndUploadFile(bool fromCamera) async {
    String? filePath;
    Uint8List? fileBytes;
    String? fileName;

    if (fromCamera) {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        if (kIsWeb) {
          fileBytes = await image.readAsBytes();
          fileName = image.name;
        } else {
          filePath = image.path;
        }
      }
    } else {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'png', 'pdf', 'jpeg'],
        withData: kIsWeb,
      );
      if (result != null) {
        if (kIsWeb) {
          fileBytes = result.files.single.bytes;
          fileName = result.files.single.name;
        } else {
          filePath = result.files.single.path;
        }
      }
    }

    if (filePath == null && fileBytes == null) return;

    setState(() {
      _isUploading = true;
      _statusMessage = "AI is digitizing your report... Please wait.";
    });

    try {
      var request = NetworkManager.instance.multipartRequest(
          'POST', '${ApiRoutes.baseUrl}/api/patient-portal/reports/upload');
      request.fields['patient_id'] = widget.patientId.toString();

      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes('file', fileBytes!,
            filename: fileName ?? 'report.pdf'));
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', filePath!));
      }

      var response = await request.send();

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Report digitized successfully!")));
          context.go(_parentPath(context));
        }
      } else {
        setState(() => _statusMessage = "Failed to upload. Please try again.");
      }
    } catch (e) {
      setState(() => _statusMessage = "An error occurred.");
    } finally {
      if (mounted &&
          _statusMessage != "Failed to upload. Please try again." &&
          _statusMessage != "An error occurred.") {
        setState(() => _isUploading = false);
      }
    }
  }

  // Reached via context.go() from either the real, authenticated patient
  // view (/patients/:id) or the pre-auth demo (/patient-demo/:id) — go()
  // replaces the whole route stack, so the default back button has
  // nothing to pop to; send it back to whichever parent opened this.
  String _parentPath(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    final base =
        currentPath.startsWith('/patient-demo') ? '/patient-demo' : '/patients';
    return '$base/${widget.patientId}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Upload Medical Report"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(_parentPath(context)),
        ),
      ),
      body: Center(
        child: _isUploading
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(_statusMessage,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  const Text(
                      "This usually takes 10-30 seconds depending on hardware.",
                      style: TextStyle(color: Colors.grey)),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_upload_outlined,
                      size: 100,
                      color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(height: 24),
                  const Text("Select a document to upload",
                      style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 8),
                  const Text("Supported formats: JPG, PNG, PDF"),
                  const SizedBox(height: 48),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _pickAndUploadFile(true),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text("Camera"),
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12)),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => _pickAndUploadFile(false),
                        icon: const Icon(Icons.folder),
                        label: const Text("Gallery / Files"),
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12)),
                      ),
                    ],
                  )
                ],
              ),
      ),
    );
  }
}
