import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/image_upload_widget.dart';
import '../../../core/theme/app_theme.dart';

class EditCandidateDialog extends ConsumerStatefulWidget {
  final String electionId;
  final CandidateModel candidate;
  const EditCandidateDialog({super.key, required this.electionId, required this.candidate});

  @override
  ConsumerState<EditCandidateDialog> createState() => _EditCandidateDialogState();
}

class _EditCandidateDialogState extends ConsumerState<EditCandidateDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _manifestoController;
  late String _status;
  String _photoUrl = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _manifestoController = TextEditingController(text: widget.candidate.manifesto);
    _status = widget.candidate.status ?? 'draft';
    _photoUrl = widget.candidate.photoUrl ?? '';
  }

  @override
  void dispose() {
    _manifestoController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final dio = ref.read(apiClientProvider);
      await dio.patch('${ApiConstants.electionCandidates(widget.electionId)}${widget.candidate.id}/', data: {
        'manifesto': _manifestoController.text.trim(),
        'status': _status,
        'photo_url': _photoUrl,
      });
      ref.invalidate(electionProvider(widget.electionId));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Candidate'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              ImageUploadWidget(
                initialImageUrl: _photoUrl,
                placeholderText: widget.candidate.name.isNotEmpty 
                    ? widget.candidate.name[0].toUpperCase() 
                    : 'C',
                radius: 40,
                onImageUploaded: (url) => setState(() => _photoUrl = url),
              ),
              const SizedBox(height: 24),
              TextFormField(
                initialValue: widget.candidate.name,
                enabled: false,
                decoration: const InputDecoration(labelText: 'Member Name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _manifestoController,
                decoration: const InputDecoration(labelText: 'Manifesto'),
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                  DropdownMenuItem(value: 'withdrawn', child: Text('Withdrawn')),
                ],
                onChanged: (v) => setState(() => _status = v!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => context.pop(),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        LoadingButton(
          isLoading: _isLoading,
          onPressed: _submit,
          label: 'Save Changes',
        ),
      ],
    );
  }
}
