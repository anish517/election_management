import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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

  // Date/time schedule fields
  DateTime? _nominationOpenAt;
  DateTime? _nominationCloseAt;
  DateTime? _votingStartAt;
  DateTime? _votingEndAt;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.election.title);
    _descController = TextEditingController(text: widget.election.description);

    // Pre-fill existing dates if they exist
    _nominationOpenAt = _parseDate(widget.election.nominationOpenAt);
    _nominationCloseAt = _parseDate(widget.election.nominationCloseAt);
    _votingStartAt = _parseDate(widget.election.votingStartAt);
    _votingEndAt = _parseDate(widget.election.votingEndAt);
  }

  DateTime? _parseDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      return DateTime.parse(iso).toLocal();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(String label, DateTime? current, ValueSetter<DateTime> onPicked) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now.add(const Duration(days: 1)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
      helpText: 'Select date for $label',
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? now),
      helpText: 'Select time for $label',
    );
    if (time == null || !mounted) return;

    onPicked(DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final payload = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
      };

      // Only include dates if they are set
      if (_nominationOpenAt != null) payload['nomination_open_at'] = _nominationOpenAt!.toUtc().toIso8601String();
      if (_nominationCloseAt != null) payload['nomination_close_at'] = _nominationCloseAt!.toUtc().toIso8601String();
      if (_votingStartAt != null) payload['voting_start_at'] = _votingStartAt!.toUtc().toIso8601String();
      if (_votingEndAt != null) payload['voting_end_at'] = _votingEndAt!.toUtc().toIso8601String();

      final dio = ref.read(apiClientProvider);
      await dio.patch(ApiConstants.electionDetail(widget.election.id), data: payload);
      ref.invalidate(electionProvider(widget.election.id));
      ref.invalidate(electionsProvider);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Election schedule saved! Celery will automate state changes.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Not set — tap to pick';
    return DateFormat('MMM dd, yyyy  hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.edit_calendar_rounded, color: AppColors.primaryLight, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text('Edit Election', style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: 20),

                // Basic Info Section
                _buildSectionHeader('Basic Info', Icons.info_outline_rounded),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Election Title', prefixIcon: Icon(Icons.title_rounded)),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: 'Description (Optional)', prefixIcon: Icon(Icons.description_outlined)),
                  maxLines: 2,
                ),

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),

                // Automated Timer Section
                _buildSectionHeader('⏱️ Automated Timer Schedule', Icons.schedule_rounded),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_rounded, color: AppColors.accent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Celery & Redis are running! Set dates below and the system will automatically advance the election state every minute.',
                          style: TextStyle(color: AppColors.accent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Date pickers
                _buildDateRow(
                  icon: Icons.person_add_alt_1_outlined,
                  color: AppColors.stateNominations,
                  label: 'Nominations Open',
                  subtitle: 'State → nominations_open',
                  value: _nominationOpenAt,
                  onTap: () => _pickDateTime('Nominations Open', _nominationOpenAt, (d) => setState(() => _nominationOpenAt = d)),
                  onClear: () => setState(() => _nominationOpenAt = null),
                ),
                const SizedBox(height: 10),
                _buildDateRow(
                  icon: Icons.lock_clock_outlined,
                  color: AppColors.warning,
                  label: 'Nominations Close',
                  subtitle: 'State → nominations_closed',
                  value: _nominationCloseAt,
                  onTap: () => _pickDateTime('Nominations Close', _nominationCloseAt, (d) => setState(() => _nominationCloseAt = d)),
                  onClear: () => setState(() => _nominationCloseAt = null),
                ),
                const SizedBox(height: 10),
                _buildDateRow(
                  icon: Icons.how_to_vote_rounded,
                  color: AppColors.stateVoting,
                  label: 'Voting Opens',
                  subtitle: 'State → voting_open 🗳️',
                  value: _votingStartAt,
                  onTap: () => _pickDateTime('Voting Opens', _votingStartAt, (d) => setState(() => _votingStartAt = d)),
                  onClear: () => setState(() => _votingStartAt = null),
                ),
                const SizedBox(height: 10),
                _buildDateRow(
                  icon: Icons.lock_outline_rounded,
                  color: AppColors.error,
                  label: 'Voting Closes',
                  subtitle: 'State → voting_closed 🔒 + auto-tally',
                  value: _votingEndAt,
                  onTap: () => _pickDateTime('Voting Closes', _votingEndAt, (d) => setState(() => _votingEndAt = d)),
                  onClear: () => setState(() => _votingEndAt = null),
                ),

                const SizedBox(height: 24),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : () => context.pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: LoadingButton(
                        isLoading: _isLoading,
                        onPressed: _submit,
                        label: 'Save Schedule',
                        icon: Icons.save_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primaryLight),
        const SizedBox(width: 6),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryLight, fontSize: 13)),
      ],
    );
  }

  Widget _buildDateRow({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required DateTime? value,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    final isSet = value != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSet ? color.withValues(alpha: 0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSet ? color.withValues(alpha: 0.4) : AppColors.surfaceVariant),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    isSet ? _formatDate(value) : subtitle,
                    style: TextStyle(
                      color: isSet ? AppColors.textSecondary : AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (isSet)
              IconButton(
                icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textMuted),
                onPressed: onClear,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}
