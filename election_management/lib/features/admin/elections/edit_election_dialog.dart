import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../core/theme/app_theme.dart';

class EditElectionDialog extends ConsumerStatefulWidget {
  final ElectionModel election;
  const EditElectionDialog({super.key, required this.election});

  @override
  ConsumerState<EditElectionDialog> createState() => _EditElectionDialogState();
}

class _EditElectionDialogState extends ConsumerState<EditElectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.election.title);
    _descController = TextEditingController(text: widget.election.description);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final dio = ref.read(apiClientProvider);
      await dio.patch(ApiConstants.electionDetail(widget.election.id), data: {
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
      });
      ref.invalidate(electionProvider(widget.election.id));
      ref.invalidate(electionsProvider);
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
      title: const Text('Edit Election'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Election Title'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(labelText: 'Description (Optional)'),
                maxLines: 3,
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
