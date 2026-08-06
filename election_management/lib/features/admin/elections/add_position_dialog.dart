import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/widgets/loading_button.dart';

class AddPositionDialog extends ConsumerStatefulWidget {
  final String electionId;
  const AddPositionDialog({super.key, required this.electionId});

  @override
  ConsumerState<AddPositionDialog> createState() => _AddPositionDialogState();
}

class _AddPositionDialogState extends ConsumerState<AddPositionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _seatsController = TextEditingController(text: '1');
  String _votingMethod = 'fptp';
  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _seatsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionPositions(widget.electionId), data: {
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'seats_available': int.parse(_seatsController.text),
        'voting_method': _votingMethod,
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
      title: const Text('Add Position'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Position Title (e.g. President)'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(labelText: 'Description (Optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _seatsController,
                decoration: const InputDecoration(labelText: 'Seats Available'),
                keyboardType: TextInputType.number,
                validator: (v) => int.tryParse(v ?? '') == null ? 'Invalid' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _votingMethod,
                decoration: const InputDecoration(labelText: 'Voting Method'),
                items: const [
                  DropdownMenuItem(value: 'fptp', child: Text('First Past The Post')),
                  DropdownMenuItem(value: 'ranked', child: Text('Ranked Choice (IRV)')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _votingMethod = v);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: const Text('Cancel')),
        LoadingButton(
          isLoading: _isLoading,
          onPressed: _submit,
          label: 'Add Position',
        ),
      ],
    );
  }
}
