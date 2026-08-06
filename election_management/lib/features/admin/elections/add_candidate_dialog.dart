import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';

class AddCandidateDialog extends ConsumerStatefulWidget {
  final ElectionModel election;
  const AddCandidateDialog({super.key, required this.election});

  @override
  ConsumerState<AddCandidateDialog> createState() => _AddCandidateDialogState();
}

class _AddCandidateDialogState extends ConsumerState<AddCandidateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _manifestoController = TextEditingController();
  final _slateController = TextEditingController();
  
  String? _selectedPositionId;
  String? _selectedMemberId;
  String _selectedStatus = 'approved';

  @override
  void dispose() {
    _manifestoController.dispose();
    _slateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPositionId == null || _selectedMemberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a position and a member')));
      return;
    }

    try {
      await ref.read(addCandidateProvider.notifier).addCandidate(
        electionId: widget.election.id,
        positionId: _selectedPositionId!,
        memberId: _selectedMemberId!,
        manifesto: _manifestoController.text.trim(),
        slateName: _slateController.text.trim(),
        status: _selectedStatus,
      );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);
    final state = ref.watch(addCandidateProvider);

    return AlertDialog(
      title: const Text('Add Candidate'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.election.positions.isEmpty)
                const Text('Please add a position first.')
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedPositionId,
                  decoration: const InputDecoration(labelText: 'Position'),
                  items: widget.election.positions.map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.title),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedPositionId = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
              const SizedBox(height: 16),
              
              membersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error loading members: $e'),
                data: (members) {
                  if (members.isEmpty) return const Text('No members found in organization.');
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedMemberId,
                    decoration: const InputDecoration(labelText: 'Member (Voter)'),
                    items: members.map((m) => DropdownMenuItem(
                      value: m.id,
                      child: Text('${m.fullName} (${m.email})'),
                    )).toList(),
                    onChanged: (v) => setState(() => _selectedMemberId = v),
                    validator: (v) => v == null ? 'Required' : null,
                  );
                },
              ),
              
              const SizedBox(height: 16),
              TextFormField(
                controller: _manifestoController,
                decoration: const InputDecoration(labelText: 'Manifesto / Bio'),
                maxLines: 3,
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _slateController,
                decoration: const InputDecoration(labelText: 'Slate Name (Optional)'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedStatus,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'draft', child: Text('Draft')),
                  DropdownMenuItem(value: 'submitted', child: Text('Submitted')),
                  DropdownMenuItem(value: 'under_review', child: Text('Under Review')),
                  DropdownMenuItem(value: 'approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                  DropdownMenuItem(value: 'withdrawn', child: Text('Withdrawn')),
                ],
                onChanged: (v) => setState(() => _selectedStatus = v!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: const Text('Cancel')),
        if (widget.election.positions.isNotEmpty)
          LoadingButton(
            isLoading: state.isLoading,
            onPressed: _submit,
            label: 'Submit Candidate',
          ),
      ],
    );
  }
}
