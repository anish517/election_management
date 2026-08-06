import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../core/theme/app_theme.dart';

class EditPositionDialog extends ConsumerStatefulWidget {
  final String electionId;
  final PositionModel position;
  const EditPositionDialog({super.key, required this.electionId, required this.position});

  @override
  ConsumerState<EditPositionDialog> createState() => _EditPositionDialogState();
}

class _EditPositionDialogState extends ConsumerState<EditPositionDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _seatsController;
  late String _votingMethod;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.position.title);
    _seatsController = TextEditingController(text: widget.position.seatsAvailable.toString());
    _votingMethod = widget.position.votingMethod;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _seatsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final dio = ref.read(apiClientProvider);
      // Django viewset detail url typically uses the object ID
      // ApiConstants might need an endpoint for individual positions
      // We will use /api/v1/elections/{election_id}/positions/{id}/
      await dio.patch('${ApiConstants.electionPositions(widget.electionId)}${widget.position.id}/', data: {
        'title': _titleController.text.trim(),
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
      title: const Text('Edit Position'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Position Title'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _seatsController,
                decoration: const InputDecoration(
                  labelText: 'Number of Winners (Seats Available)',
                  helperText: 'E.g., 1 for President.',
                ),
                keyboardType: TextInputType.number,
                validator: (v) => int.tryParse(v ?? '') == null ? 'Invalid number' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _votingMethod,
                decoration: const InputDecoration(labelText: 'Voting Method'),
                items: const [
                  DropdownMenuItem(value: 'fptp', child: Text('First Past The Post')),
                  DropdownMenuItem(value: 'approval', child: Text('Approval Voting')),
                ],
                onChanged: (v) => setState(() => _votingMethod = v!),
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
