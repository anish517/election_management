import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/theme/app_theme.dart';

class ImageUploadWidget extends ConsumerStatefulWidget {
  final String? initialImageUrl;
  final String placeholderText;
  final double radius;
  final Function(String url) onImageUploaded;

  const ImageUploadWidget({
    super.key,
    this.initialImageUrl,
    this.placeholderText = '?',
    this.radius = 50,
    required this.onImageUploaded,
  });

  @override
  ConsumerState<ImageUploadWidget> createState() => _ImageUploadWidgetState();
}

class _ImageUploadWidgetState extends ConsumerState<ImageUploadWidget> {
  bool _isUploading = false;
  String? _currentImageUrl;

  @override
  void initState() {
    super.initState();
    _currentImageUrl = widget.initialImageUrl;
  }

  Future<void> _pickAndUpload() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() => _isUploading = true);

      final fileBytes = result.files.first.bytes;
      final fileName = result.files.first.name;

      if (fileBytes == null) {
        throw Exception('Could not read file data');
      }

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
      });

      final dio = ref.read(apiClientProvider);
      final response = await dio.post(ApiConstants.fileUpload, data: formData);

      if (response.data != null && response.data['url'] != null) {
        final url = response.data['url'] as String;
        setState(() => _currentImageUrl = url);
        widget.onImageUploaded(url);
      } else {
        throw Exception('No URL returned from server');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isUploading ? null : _pickAndUpload,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircleAvatar(
            radius: widget.radius,
            backgroundColor: AppColors.primaryLight.withValues(alpha: 0.2),
            backgroundImage: (_currentImageUrl != null && _currentImageUrl!.isNotEmpty)
                ? NetworkImage(_currentImageUrl!)
                : null,
            child: (_currentImageUrl == null || _currentImageUrl!.isEmpty)
                ? Text(
                    widget.placeholderText,
                    style: TextStyle(
                      fontSize: widget.radius * 0.6,
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          if (_isUploading)
            Container(
              width: widget.radius * 2,
              height: widget.radius * 2,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const CircularProgressIndicator(color: Colors.white),
            )
          else
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
