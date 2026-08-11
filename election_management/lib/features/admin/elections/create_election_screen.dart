import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/responsive_layout.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';

class CreateElectionScreen extends ConsumerStatefulWidget {
  const CreateElectionScreen({super.key});

  @override
  ConsumerState<CreateElectionScreen> createState() => _CreateElectionScreenState();
}

class _CreateElectionScreenState extends ConsumerState<CreateElectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  DateTime? _nominationOpenAt;
  DateTime? _nominationCloseAt;
  DateTime? _votingStartAt;
  DateTime? _votingEndAt;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _selectDateTime(DateTime? current, Function(DateTime) onSelected) async {
    NepaliDateTime initial = current?.toNepaliDateTime() ?? NepaliDateTime.now();
    final date = await showMaterialDatePicker(
      context: context,
      initialDate: initial,
      firstDate: NepaliDateTime(2070, 1, 1),
      lastDate: NepaliDateTime(2100, 12, 30),
    );
    if (date == null || !mounted) return;
    
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
    );
    if (time == null) return;

    setState(() {
      final ndt = NepaliDateTime(date.year, date.month, date.day, time.hour, time.minute);
      onSelected(ndt.toDateTime());
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await ref.read(createElectionProvider.notifier).createElection(
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        nominationOpenAt: _nominationOpenAt,
        nominationCloseAt: _nominationCloseAt,
        votingStartAt: _votingStartAt,
        votingEndAt: _votingEndAt,
      );
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Election created as Draft!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createElectionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Election')),
      body: ResponsiveFormWrapper(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Election Title',
                      prefixIcon: Icon(Icons.how_to_vote),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 3,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 24),
                  const Text('Schedule (Optional, for Celery)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildDateTile('Nomination Opens', _nominationOpenAt, (d) => _nominationOpenAt = d),
                  _buildDateTile('Nomination Closes', _nominationCloseAt, (d) => _nominationCloseAt = d),
                  _buildDateTile('Voting Starts', _votingStartAt, (d) => _votingStartAt = d),
                  _buildDateTile('Voting Ends', _votingEndAt, (d) => _votingEndAt = d),
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
        ),
      ),
      ),
    );
  }

  Widget _buildDateTile(String label, DateTime? value, Function(DateTime) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          TextButton.icon(
            onPressed: () => _selectDateTime(value, onChanged),
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: Text(value != null ? NepaliDateFormat('MMM d, yyyy - h:mm a').format(value.toNepaliDateTime()) : 'Select Date'),
          ),
        ],
      ),
    );
  }
}
