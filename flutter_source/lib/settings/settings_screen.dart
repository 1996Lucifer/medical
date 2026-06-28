import 'dart:convert';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show GlassCard, GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Map<String, dynamic>> _staffList = [];
  List<Map<String, dynamic>> _savedCameras = [];

  // ── Camera API ────────────────────────────────────────────────────────────
  Future<void> _fetchCameras() async {
    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.cameras)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _savedCameras = (jsonDecode(resp.body) as List<dynamic>).cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  // ── Staff API ─────────────────────────────────────────────────────────────
  Future<void> _fetchStaff() async {
    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.staff)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _staffList = (jsonDecode(resp.body) as List<dynamic>).cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white.withOpacity(0.6),
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.black.withOpacity(0.05), height: 1.0),
        ),
      ),
      body: GlassBackground(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.shade50,
                        child: Icon(Icons.manage_accounts_rounded, color: Colors.teal.shade700),
                      ),
                      title: const Text(
                        'Manage Staff',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      subtitle: const Text('Add, remove, or update staff photos for AI recognition'),
                      onTap: _showStaffManagementDialog,
                    ),
                    const Divider(height: 1, thickness: 1, indent: 20, endIndent: 20),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.shade50,
                        child: Icon(Icons.videocam_rounded, color: Colors.teal.shade700),
                      ),
                      title: const Text(
                        'Manage Cameras',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      subtitle: const Text('Add or remove registered RTSP camera sources'),
                      onTap: _showCameraSourceDialog,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Camera source management dialog ────────────────────────────────────────
  Future<void> _showCameraSourceDialog() async {
    await _fetchCameras();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        final dialogWidth = screenWidth > 500 ? 400.0 : screenWidth * 0.85;
        return AlertDialog(
          title: const Text('Camera Sources'),
          content: SizedBox(
            width: dialogWidth,
            height: 400,
            child: Column(children: [
              Expanded(
                child: _savedCameras.isEmpty
                    ? const Center(child: Text('No cameras saved yet.'))
                    : ListView.builder(
                        itemCount: _savedCameras.length,
                        itemBuilder: (_, i) {
                          final c = _savedCameras[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.videocam),
                            title: Text(c['name'] as String),
                            subtitle: Text(c['location'] ?? c['rtsp_url']),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18, color: Colors.grey),
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    await _showEditCameraDialog(c);
                                    await _showCameraSourceDialog();
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18, color: Colors.red),
                                  onPressed: () async {
                                    final resp = await NetworkManager.instance.delete(
                                        ApiRoutes.camera(c['id']));
                                    
                                    if (resp.statusCode != 200) {
                                      if (ctx.mounted) {
                                        String errorMsg = 'Failed to delete camera.';
                                        try {
                                          errorMsg = jsonDecode(resp.body)['detail'] ?? errorMsg;
                                        } catch (_) {}
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
                                        );
                                      }
                                    } else {
                                      await _fetchCameras();
                                      setD(() {});
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _showAddCameraDialog();
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Camera'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _showAddCameraDialog() async {
    final nameCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('Add Camera Source'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Camera Name', hintText: 'e.g. Main Entrance'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: locationCtrl,
                decoration: const InputDecoration(
                    labelText: 'Location (optional)',
                    hintText: 'e.g. Ground Floor, Block A'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                    labelText: 'RTSP URL', hintText: 'rtsp://user:pass@ip:554/stream1'),
              ),
              if (isSaving) ...[const SizedBox(height: 12), const CircularProgressIndicator()],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                if (nameCtrl.text.isEmpty || urlCtrl.text.isEmpty) return;
                setD(() => isSaving = true);
                final resp = await NetworkManager.instance.post(
                  ApiRoutes.cameras,
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'name': nameCtrl.text,
                    'location': locationCtrl.text.isEmpty ? null : locationCtrl.text,
                    'rtsp_url': urlCtrl.text,
                  }),
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  if (resp.statusCode == 200) {
                    await _showCameraSourceDialog(); // Re-open management dialog
                  }
                }
                if (ctx.mounted) {
                  setD(() => isSaving = false);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _showEditCameraDialog(Map<String, dynamic> camera) async {
    final nameCtrl = TextEditingController(text: camera['name'] ?? '');
    final locationCtrl = TextEditingController(text: camera['location'] ?? '');
    final urlCtrl = TextEditingController(text: camera['rtsp_url'] ?? '');
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('Edit Camera Source'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Camera Name', hintText: 'e.g. Main Entrance'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: locationCtrl,
                decoration: const InputDecoration(
                    labelText: 'Location (optional)',
                    hintText: 'e.g. Ground Floor, Block A'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                    labelText: 'RTSP URL', hintText: 'rtsp://user:pass@ip:554/stream1'),
              ),
              if (isSaving) ...[const SizedBox(height: 12), const CircularProgressIndicator()],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                if (nameCtrl.text.isEmpty || urlCtrl.text.isEmpty) return;
                setD(() => isSaving = true);
                final resp = await NetworkManager.instance.put(
                  ApiRoutes.camera(camera['id']),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'name': nameCtrl.text,
                    'location': locationCtrl.text.isEmpty ? null : locationCtrl.text,
                    'rtsp_url': urlCtrl.text,
                  }),
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  if (resp.statusCode == 200) {
                    await _showCameraSourceDialog(); // Re-open management dialog
                  }
                }
                if (ctx.mounted) {
                  setD(() => isSaving = false);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
  }

  // ── Staff management dialogs ───────────────────────────────────────────────
  Future<void> _showStaffManagementDialog() async {
    await _fetchStaff();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        final dialogWidth = screenWidth > 500 ? 400.0 : screenWidth * 0.85;
        return AlertDialog(
          title: const Text('Staff Management'),
          content: SizedBox(
            width: dialogWidth,
            height: 420,
            child: Column(children: [
              Expanded(
                child: _staffList.isEmpty
                    ? const Center(child: Text('No staff registered yet.'))
                    : ListView.builder(
                        itemCount: _staffList.length,
                        itemBuilder: (_, i) {
                          final s = _staffList[i];
                          final photoCount = s['photo_count'] ?? 1;
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              child: Text((s['name'] as String)[0].toUpperCase()),
                            ),
                            title: Text(s['name'] as String),
                            subtitle: Text('$photoCount photo${photoCount == 1 ? '' : 's'}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                                  tooltip: 'Edit staff name',
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    await _showEditStaffDialog(s);
                                    await _showStaffManagementDialog();
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.photo_library, size: 20, color: Colors.blue),
                                  tooltip: 'Manage photos',
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    await _showManagePhotosDialog(s['id'] as int, s['name'] as String);
                                    await _showStaffManagementDialog();
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                  tooltip: 'Remove staff',
                                  onPressed: () async {
                                    await NetworkManager.instance.delete(ApiRoutes.staffMember(s['id']));
                                    await _fetchStaff();
                                    setD(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _showRegisterNewStaffDialog();
                await _showStaffManagementDialog();
              },
              icon: const Icon(Icons.person_add, size: 16),
              label: const Text('Register New'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _showRegisterNewStaffDialog() async {
    final nameController = TextEditingController();
    FilePickerResult? pickedFile;
    bool isUploading = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('Register New Staff'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                pickedFile = await FilePicker.platform.pickFiles(
                    type: FileType.image, withData: true);
                setD(() {});
              },
              icon: const Icon(Icons.face),
              label: Text(pickedFile != null ? 'Photo Selected ✓' : 'Select Front-Face Photo'),
            ),
            if (isUploading) ...[const SizedBox(height: 12), const CircularProgressIndicator()],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isUploading ? null : () async {
                if (nameController.text.isEmpty || pickedFile == null) return;
                setD(() => isUploading = true);
                try {
                  final request = NetworkManager.instance.multipartRequest(
                      'POST', ApiRoutes.staffSearch(nameController.text));
                  if (kIsWeb) {
                    request.files.add(http.MultipartFile.fromBytes('file',
                        pickedFile!.files.single.bytes!,
                        filename: pickedFile!.files.single.name));
                  } else {
                    request.files.add(await http.MultipartFile.fromPath(
                        'file', pickedFile!.files.single.path!));
                  }
                  final resp = await request.send();
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text(resp.statusCode == 200
                          ? '✓ ${nameController.text} registered!'
                          : 'Error ${resp.statusCode}'),
                    ));
                  }
                } finally {
                  if (ctx.mounted) {
                    setD(() => isUploading = false);
                  }
                }
              },
              child: const Text('Register'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _showEditStaffDialog(Map<String, dynamic> staff) async {
    final nameController = TextEditingController(text: staff['name'] ?? '');
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('Edit Staff Name'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            if (isSaving) ...[const SizedBox(height: 12), const CircularProgressIndicator()],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                if (nameController.text.isEmpty) return;
                setD(() => isSaving = true);
                final resp = await NetworkManager.instance.put(
                  ApiRoutes.staffMember(staff['id']),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'name': nameController.text}),
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (ctx.mounted) {
                  setD(() => isSaving = false);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _showManagePhotosDialog(int staffId, String staffName) async {
    List<Map<String, dynamic>> photos = [];
    bool isLoading = true;

    Future<void> fetchPhotos() async {
      try {
        final resp = await NetworkManager.instance.get(ApiRoutes.staffPhotos(staffId));
        if (resp.statusCode == 200) {
          photos = (jsonDecode(resp.body) as List<dynamic>).cast<Map<String, dynamic>>();
        }
      } catch (_) {}
    }

    await fetchPhotos();
    isLoading = false;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        final dialogWidth = screenWidth > 500 ? 400.0 : screenWidth * 0.85;
        return AlertDialog(
          title: Text('Manage Photos for $staffName'),
          content: SizedBox(
            width: dialogWidth,
            height: 400,
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : photos.isEmpty
                    ? const Center(child: Text('No photos found.'))
                    : ListView.builder(
                        itemCount: photos.length,
                        itemBuilder: (_, i) {
                          final p = photos[i];
                          return ListTile(
                            leading: const Icon(Icons.image),
                            title: Text(p['label'] ?? 'photo'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () async {
                                await NetworkManager.instance.delete(ApiRoutes.staffPhotoDelete(staffId, p['id']));
                                setD(() => isLoading = true);
                                await fetchPhotos();
                                setD(() => isLoading = false);
                              },
                            ),
                          );
                        },
                      ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _showAddPhotoDialog(staffId, staffName);
                await _showManagePhotosDialog(staffId, staffName);
              },
              icon: const Icon(Icons.add_a_photo, size: 16),
              label: const Text('Add Photo'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _showAddPhotoDialog(int staffId, String staffName) async {
    FilePickerResult? pickedFile;
    bool isUploading = false;
    String selectedLabel = 'side_left';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: Text('Add Photo for $staffName'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Select angle:'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: ['side_left', 'side_right', 'angled_down', 'other'].map((label) => ChoiceChip(
                label: Text(label.replaceAll('_', ' ')),
                selected: selectedLabel == label,
                onSelected: (sel) { if (sel) setD(() => selectedLabel = label); },
              )).toList(),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () async {
                pickedFile = await FilePicker.platform.pickFiles(
                    type: FileType.image, withData: true);
                setD(() {});
              },
              icon: const Icon(Icons.add_a_photo),
              label: Text(pickedFile != null ? 'Photo Selected ✓' : 'Select Photo'),
            ),
            if (isUploading) ...[const SizedBox(height: 12), const CircularProgressIndicator()],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: (isUploading || pickedFile == null) ? null : () async {
                setD(() => isUploading = true);
                try {
                  final request = NetworkManager.instance.multipartRequest(
                      'POST', ApiRoutes.staffPhotoUpload(staffId, selectedLabel));
                  if (kIsWeb) {
                    request.files.add(http.MultipartFile.fromBytes('file',
                        pickedFile!.files.single.bytes!,
                        filename: pickedFile!.files.single.name));
                  } else {
                    request.files.add(await http.MultipartFile.fromPath(
                        'file', pickedFile!.files.single.path!));
                  }
                  final resp = await request.send();
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text(resp.statusCode == 200
                          ? '✓ "$selectedLabel" photo added for $staffName'
                          : 'Error ${resp.statusCode}'),
                    ));
                  }
                } finally {
                  if (ctx.mounted) {
                    setD(() => isUploading = false);
                  }
                }
              },
              child: const Text('Upload Photo'),
            ),
          ],
        );
      }),
    );
  }
}
