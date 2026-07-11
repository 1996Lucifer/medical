import 'dart:convert';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show GlassCard, GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'live_face_setup_screen.dart';

class ManageStaffScreen extends StatefulWidget {
  const ManageStaffScreen({super.key});

  @override
  State<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends State<ManageStaffScreen> {
  List<Map<String, dynamic>> _staffList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchStaff();
  }

  Future<void> _fetchStaff() async {
    setState(() => _isLoading = true);
    try {
      final resp = await NetworkManager.instance
          .get(ApiRoutes.staff)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _staffList = (jsonDecode(resp.body) as List<dynamic>)
              .cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Manage Staff',
          style:
              TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white.withOpacity(0.6),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: GlassBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Staff Directory',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A)),
                        ),
                        ElevatedButton.icon(
                          onPressed: _showRegisterNewStaffDialog,
                          icon: const Icon(Icons.person_add, size: 18),
                          label: const Text('Register New'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _isLoading && _staffList.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : _staffList.isEmpty
                              ? const Center(
                                  child: Text('No staff registered yet.',
                                      style: TextStyle(fontSize: 16)))
                              : ListView.builder(
                                  itemCount: _staffList.length,
                                  itemBuilder: (context, index) {
                                    final staff = _staffList[index];
                                    return _buildStaffCard(staff);
                                  },
                                ),
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

  Widget _buildStaffCard(Map<String, dynamic> staff) {
    final photoUrl = staff['photo_url'] != null
        ? '${ApiRoutes.baseUrl}${staff['photo_url']}'
        : null;
    final photoCount = staff['photo_count'] ?? 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: GlassCard(
        padding: const EdgeInsets.all(0),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey('staff_${staff['id']}'),
            maintainState: true,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.teal.shade50,
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null
                  ? Text((staff['name'] as String)[0].toUpperCase(),
                      style: const TextStyle(fontSize: 20))
                  : null,
            ),
            title: Text(staff['name'] as String,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Text(
                '$photoCount photo${photoCount == 1 ? '' : 's'} registered'),
            children: [
              const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
              _StaffDetailsView(
                staffId: staff['id'] as int,
                staffName: staff['name'] as String,
                onUpdate: _fetchStaff,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRegisterNewStaffDialog() async {
    final nameController = TextEditingController();
    FilePickerResult? pickedFile;
    bool isUploading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Register New Staff',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Provide a full name to begin Live Face Setup.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: nameController,
                    onChanged: (val) => setD(() {}),
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Colors.blue, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (isUploading)
                    const Center(child: CircularProgressIndicator())
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 16)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: nameController.text.isEmpty
                              ? null
                              : () async {
                                  setD(() => isUploading = true);
                                  try {
                                    final resp = await NetworkManager.instance
                                        .post(ApiRoutes.staffSearch(
                                            nameController.text));
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                      if (resp.statusCode == 200) {
                                        final staffData = jsonDecode(resp.body);
                                        final newStaffId = staffData['id'];

                                        // Navigate to Live Setup immediately
                                        final result = await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                LiveFaceSetupScreen(
                                                    staffId: newStaffId),
                                          ),
                                        );

                                        if (result == true) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      '✓ 3D Face Profile successfully registered!')));
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      '✓ ${nameController.text} registered, but face setup was skipped.')));
                                        }

                                        _fetchStaff();
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(
                                                    'Error registering staff (Code: ${resp.statusCode})')));
                                      }
                                    }
                                  } finally {
                                    if (ctx.mounted)
                                      setD(() => isUploading = false);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Start Live Setup',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _StaffDetailsView extends StatefulWidget {
  final int staffId;
  final String staffName;
  final VoidCallback onUpdate;

  const _StaffDetailsView({
    required this.staffId,
    required this.staffName,
    required this.onUpdate,
  });

  @override
  State<_StaffDetailsView> createState() => _StaffDetailsViewState();
}

class _StaffDetailsViewState extends State<_StaffDetailsView> {
  List<Map<String, dynamic>> _photos = [];
  bool _isLoadingPhotos = true;

  @override
  void initState() {
    super.initState();
    _fetchPhotos();
  }

  Future<void> _fetchPhotos() async {
    setState(() => _isLoadingPhotos = true);
    try {
      final resp = await NetworkManager.instance
          .get(ApiRoutes.staffPhotos(widget.staffId));
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _photos = (jsonDecode(resp.body) as List<dynamic>)
              .cast<Map<String, dynamic>>();
          _isLoadingPhotos = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingPhotos = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPhotos = false);
    }
  }

  Future<void> _deleteStaff() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Staff'),
        content: Text(
            'Are you sure you want to completely remove ${widget.staffName}? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final resp = await NetworkManager.instance
            .delete(ApiRoutes.staffMember(widget.staffId));
        if (resp.statusCode == 200) {
          widget.onUpdate();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✓ Staff member removed')));
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Failed to delete: ${resp.statusCode}')));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _editName() async {
    final nameController = TextEditingController(text: widget.staffName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Staff Name'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Full Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != widget.staffName) {
      await NetworkManager.instance.put(
        ApiRoutes.staffMember(widget.staffId),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': newName}),
      );
      widget.onUpdate();
    }
  }

  Future<void> _deletePhoto(int photoId) async {
    final resp = await NetworkManager.instance
        .delete(ApiRoutes.staffPhotoDelete(widget.staffId, photoId));
    if (resp.statusCode == 200) {
      _fetchPhotos();
      widget.onUpdate();
    }
  }

  Future<void> _uploadAnglePhoto(String angleLabel) async {
    FilePickerResult? pickedFile = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (pickedFile == null) return;

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uploading $angleLabel photo...')));

    try {
      final request = NetworkManager.instance.multipartRequest(
          'POST', ApiRoutes.staffPhotoUpload(widget.staffId, angleLabel));
      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes(
            'file', pickedFile.files.single.bytes!,
            filename: pickedFile.files.single.name));
      } else {
        request.files.add(await http.MultipartFile.fromPath(
            'file', pickedFile.files.single.path!));
      }
      final resp = await request.send();
      if (mounted) {
        if (resp.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✓ Photo uploaded successfully!')));
          _fetchPhotos();
          widget.onUpdate();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Upload failed with status ${resp.statusCode}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error uploading photo')));
      }
    }
  }

  Future<void> _startLiveSetup() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiveFaceSetupScreen(staffId: widget.staffId),
      ),
    );

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ 3D Face Profile successfully registered!')));
      _fetchPhotos();
      widget.onUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Manage ${widget.staffName}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              TextButton.icon(
                onPressed: _editName,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit Name'),
              ),
              TextButton.icon(
                onPressed: _deleteStaff,
                icon: const Icon(Icons.delete_forever,
                    size: 16, color: Colors.red),
                label: const Text('Remove Staff',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Additional Photos for AI Recognition:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Upload photos from various angles to improve facial recognition accuracy.',
              style: TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 16),
          if (_isLoadingPhotos)
            const SizedBox(
                height: 100, child: Center(child: CircularProgressIndicator()))
          else if (_photos.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Column(
                children: [
                  Icon(Icons.photo_library_outlined,
                      size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('No additional photos uploaded yet.',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _photos.map((photo) {
                final photoUrl = photo['photo_url'] != null
                    ? '${ApiRoutes.baseUrl}${photo['photo_url']}'
                    : null;
                return Stack(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                        image: photoUrl != null
                            ? DecorationImage(
                                image: NetworkImage(photoUrl),
                                fit: BoxFit.cover)
                            : null,
                      ),
                      child: photoUrl == null
                          ? const Center(
                              child: Icon(Icons.image, color: Colors.grey))
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(8),
                              bottomRight: Radius.circular(8)),
                        ),
                        child: Text(
                          (photo['label'] as String?)
                                  ?.replaceAll('_', ' ')
                                  .toUpperCase() ??
                              'PHOTO',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _deletePhoto(photo['id'] as int),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          const SizedBox(height: 24),
          const Text('Guided 3D Registration (Recommended)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
              'Record a short 5-second video slowly rolling your head around. The AI will automatically extract all necessary angles.',
              style: TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _startLiveSetup,
              icon: const Icon(Icons.camera_front),
              label: const Text('Start Live Interactive Setup'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade50,
                foregroundColor: Colors.teal.shade700,
                elevation: 0,
                side: BorderSide(color: Colors.teal.shade200),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 16),
          const Text('Manual Fallback Registration',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildUploadButton('front', Icons.face),
              _buildUploadButton('side_left', Icons.turn_left),
              _buildUploadButton('side_right', Icons.turn_right),
              _buildUploadButton('angled_down', Icons.arrow_downward),
              _buildUploadButton('other', Icons.more_horiz),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUploadButton(String label, IconData icon) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label.replaceAll('_', ' ')),
      onPressed: () => _uploadAnglePhoto(label),
      backgroundColor: Colors.blue.shade50,
      side: BorderSide(color: Colors.blue.shade200),
    );
  }
}
