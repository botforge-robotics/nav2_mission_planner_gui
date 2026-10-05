import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';

class RobotMediaScreen extends StatefulWidget {
  const RobotMediaScreen({super.key});

  @override
  State<RobotMediaScreen> createState() => _RobotMediaScreenState();
}

class _RobotMediaScreenState extends State<RobotMediaScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _media = [];
  String _filter = 'all'; // 'all', 'image', 'video'

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  SdkApiService? _getApi() {
    final robot = context.read<ConnectionProvider>().robot;
    if (robot == null) return null;
    return SdkApiService(robot.ip);
  }

  Future<void> _loadMedia() async {
    final api = _getApi();
    if (api == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Robot not connected';
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await api.listRobotMedia();
      if (!mounted) return;
      setState(() {
        _media = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load media: $e';
        _loading = false;
      });
    }
  }

  Future<void> _pickAndUploadMedia() async {
    final api = _getApi();
    if (api == null) return;

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
          'bmp',
          'svg',
          'mp4',
          'webm',
          'mov',
          'mkv',
          'avi'
        ],
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      if (!mounted) return;

      // Show uploading progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text('Uploading media files to robot...'),
              ),
            ],
          ),
        ),
      );

      int uploadedCount = 0;
      for (final file in result.files) {
        List<int>? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          try {
            bytes = await io.File(file.path!).readAsBytes();
          } catch (_) {}
        }
        if (bytes == null) continue;
        await api.uploadRobotMediaFile(
          bytes: bytes,
          filename: file.name,
        );
        uploadedCount++;
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // dismiss dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Successfully uploaded $uploadedCount file(s) to robot media library.'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadMedia();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // dismiss dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _deleteFile(String filename) async {
    final api = _getApi();
    if (api == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete File?'),
        content: Text(
          'Are you sure you want to permanently delete "$filename" from the robot\'s storage? '
          'It will be removed from the onboard media player immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await api.deleteRobotMedia(filename);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "$filename" from robot.')),
        );
        _loadMedia();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete file: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _previewItem(Map<String, dynamic> item) {
    final url = item['url'] as String? ?? '';
    final filename = item['filename'] as String? ?? '';
    final isVideo = (item['type'] == 'video') ||
        filename.endsWith('.mp4') ||
        filename.endsWith('.webm');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(isVideo ? Icons.videocam_rounded : Icons.image_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      filename,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.danger),
                    tooltip: 'Delete File',
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteFile(filename);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 500),
              child: isVideo
                  ? Container(
                      height: 300,
                      color: const Color(0xFF1E293B),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.play_circle_fill_rounded,
                              size: 64, color: AppColors.primary),
                          const SizedBox(height: 12),
                          Text(
                            'Video file: $filename',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Plays in full screen on robot onboard screen (Slide 2)',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Failed to load image preview',
                              style: TextStyle(color: Colors.white70)),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  String _formatBytes(dynamic bytes) {
    if (bytes == null) return '';
    final num b = bytes is num ? bytes : num.tryParse(bytes.toString()) ?? 0;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _media.where((m) {
      if (_filter == 'all') return true;
      final type = m['type'] as String? ?? '';
      return type == _filter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Robot Media & Signage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Media List',
            onPressed: _loadMedia,
          ),
        ],
      ),
      body: SafeArea(
        child: CenteredFormColumn(
          maxWidth: Breakpoints.of(context) == DeviceClass.desktop ? 960 : 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Notice Banner explaining DND Mode
              Container(
                margin: const EdgeInsets.all(AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: const Color(0xFF9333EA).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF9333EA).withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🌙', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Onboard Screen Media & DND Display',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF7E22CE),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Files shared here are stored in the robot media folder and displayed on Slide 2 of the robot touchscreen. '
                            'When the robot is on the Media DND screen, navigation popups and mission overlays are muted for clean presentation.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Action Toolbar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  children: [
                    // Filter Chips
                    ChoiceChip(
                      label: Text('All (${_media.length})'),
                      selected: _filter == 'all',
                      onSelected: (_) => setState(() => _filter = 'all'),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    ChoiceChip(
                      label: Text(
                          'Images (${_media.where((m) => m['type'] == 'image').length})'),
                      selected: _filter == 'image',
                      onSelected: (_) => setState(() => _filter = 'image'),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    ChoiceChip(
                      label: Text(
                          'Videos (${_media.where((m) => m['type'] == 'video').length})'),
                      selected: _filter == 'video',
                      onSelected: (_) => setState(() => _filter = 'video'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _pickAndUploadMedia,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('Share / Upload'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Media List / Grid Body
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    size: 48, color: AppColors.danger),
                                const SizedBox(height: 12),
                                Text(_error!,
                                    style: const TextStyle(
                                        color: AppColors.danger)),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _loadMedia,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : filtered.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.xl),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(24),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF9333EA)
                                              .withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.perm_media_rounded,
                                          size: 48,
                                          color: Color(0xFF9333EA),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'No Media Files on Robot',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Share photos or videos to showcase on the robot display.',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textSecondary),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 20),
                                      FilledButton.icon(
                                        onPressed: _pickAndUploadMedia,
                                        icon: const Icon(
                                            Icons.add_photo_alternate_rounded),
                                        label: const Text('Pick & Share Media'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: AppSpacing.sm),
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  final filename =
                                      item['filename'] as String? ?? '';
                                  final name = item['name'] as String? ?? filename;
                                  final type = item['type'] as String? ?? '';
                                  final url = item['url'] as String? ?? '';
                                  final sizeStr = _formatBytes(item['size']);
                                  final isVideo = type == 'video' ||
                                      filename.endsWith('.mp4') ||
                                      filename.endsWith('.webm');

                                  return Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () => _previewItem(item),
                                      child: Padding(
                                        padding: const EdgeInsets.all(
                                            AppSpacing.sm),
                                        child: Row(
                                          children: [
                                            // Thumbnail Box
                                            Container(
                                              width: 58,
                                              height: 58,
                                              decoration: BoxDecoration(
                                                color: Colors.black12,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child: isVideo
                                                  ? Container(
                                                      color: const Color(
                                                          0xFF1E293B),
                                                      child: const Icon(
                                                        Icons
                                                            .play_circle_fill_rounded,
                                                        color:
                                                            AppColors.primary,
                                                        size: 28,
                                                      ),
                                                    )
                                                  : Image.network(
                                                      url,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (_, __, ___) =>
                                                              const Icon(
                                                        Icons.image_rounded,
                                                        color: AppColors
                                                            .textTertiary,
                                                      ),
                                                    ),
                                            ),
                                            const SizedBox(
                                                width: AppSpacing.md),
                                            // Info
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 6,
                                                          vertical: 1.5,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: isVideo
                                                              ? const Color(
                                                                      0xFFEF4444)
                                                                  .withValues(
                                                                      alpha:
                                                                          0.15)
                                                              : const Color(
                                                                      0xFF3B82F6)
                                                                  .withValues(
                                                                      alpha:
                                                                          0.15),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                        ),
                                                        child: Text(
                                                          isVideo
                                                              ? 'VIDEO'
                                                              : 'IMAGE',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: isVideo
                                                                ? const Color(
                                                                    0xFFEF4444)
                                                                : const Color(
                                                                    0xFF3B82F6),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        sizeStr,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: AppColors
                                                              .textTertiary,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Action Buttons
                                            IconButton(
                                              icon: const Icon(
                                                Icons.visibility_outlined,
                                                size: 20,
                                              ),
                                              tooltip: 'Preview',
                                              onPressed: () =>
                                                  _previewItem(item),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                size: 20,
                                                color: AppColors.danger,
                                              ),
                                              tooltip: 'Delete File',
                                              onPressed: () =>
                                                  _deleteFile(filename),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
