import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../shared/widgets/loading_button.dart';

class CreateElectionScreen extends ConsumerStatefulWidget {
  const CreateElectionScreen({super.key});

  @override
  ConsumerState<CreateElectionScreen> createState() => _CreateElectionScreenState();
}

class _CreateElectionScreenState extends ConsumerState<CreateElectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  
  DateTime? _votingStartAt;
  DateTime? _votingEndAt;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? (DateTime.now().add(const Duration(days: 1))) : (_votingStartAt ?? DateTime.now().add(const Duration(days: 2)));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time != null) {
        setState(() {
          final fullDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
          if (isStart) {
            _votingStartAt = fullDate;
          } else {
            _votingEndAt = fullDate;
          }
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_votingStartAt == null || _votingEndAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select voting start and end dates')));
      return;
    }
    if (_votingEndAt!.isBefore(_votingStartAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End date must be after start date')));
      return;
    }

    try {
      await ref.read(createElectionProvider.notifier).createElection(
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        votingStartAt: _votingStartAt!,
        votingEndAt: _votingEndAt!,
      );
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Election created in DRAFT state!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  String _formatDate(DateTime? d) => d == null ? 'Not set' : '${d.toLocal().toString().substring(0,16)}';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createElectionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Election')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Election Title'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(true),
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text('Voting Start:\n${_formatDate(_votingStartAt)}'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(false),
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text('Voting End:\n${_formatDate(_votingEndAt)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: LoadingButton(
                  isLoading: state.isLoading,
                  onPressed: () {
                    if (mounted) _submit();
                  },
                  label: 'Create Draft',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
