import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../core/theme/app_theme.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';

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
  DateTime? _votingStartAt;
  DateTime? _votingEndAt;
  DateTime? _firstVoterListDate;
  DateTime? _voterListClaimDate;
  DateTime? _finalVoterListDate;
  DateTime? _nominationOpenAt;
  DateTime? _nominationCloseAt;
  DateTime? _candidacyClaimDate;
  DateTime? _candidacyFinalDate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.election.title);
    _descController = TextEditingController(text: widget.election.description);

    // Pre-fill existing dates if they exist
    _votingStartAt = _parseDate(widget.election.votingStartAt);
    _votingEndAt = _parseDate(widget.election.votingEndAt);
    _firstVoterListDate = _parseDate(widget.election.firstVoterListDate);
    _voterListClaimDate = _parseDate(widget.election.voterListClaimDate);
    _finalVoterListDate = _parseDate(widget.election.finalVoterListDate);
    _nominationOpenAt = _parseDate(widget.election.nominationOpenAt);
    _nominationCloseAt = _parseDate(widget.election.nominationCloseAt);
    _candidacyClaimDate = _parseDate(widget.election.candidacyClaimDate);
    _candidacyFinalDate = _parseDate(widget.election.candidacyFinalDate);
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
    final now = NepaliDateTime.now();
    NepaliDateTime initial = current?.toNepaliDateTime() ?? now;
    final date = await showMaterialDatePicker(
      context: context,
      initialDate: initial,
      firstDate: NepaliDateTime(2070, 1, 1),
      lastDate: NepaliDateTime(2100, 12, 30),
      helpText: 'Select date for $label',
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
      helpText: 'Select time for $label',
    );
    if (time == null || !mounted) return;

    final ndt = NepaliDateTime(date.year, date.month, date.day, time.hour, time.minute);
    onPicked(ndt.toDateTime());
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_votingStartAt != null && _votingEndAt != null && _votingEndAt!.isBefore(_votingStartAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voting End date must be after Voting Start date.')));
      return;
    }
    if (_nominationOpenAt != null && _nominationCloseAt != null && _nominationCloseAt!.isBefore(_nominationOpenAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nomination Close date must be after Nomination Open date.')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final payload = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'voting_start_at': _votingStartAt?.toUtc().toIso8601String(),
        'voting_end_at': _votingEndAt?.toUtc().toIso8601String(),
        'first_voter_list_date': _firstVoterListDate?.toUtc().toIso8601String(),
        'voter_list_claim_date': _voterListClaimDate?.toUtc().toIso8601String(),
        'final_voter_list_date': _finalVoterListDate?.toUtc().toIso8601String(),
        'nomination_open_at': _nominationOpenAt?.toUtc().toIso8601String(),
        'nomination_close_at': _nominationCloseAt?.toUtc().toIso8601String(),
        'candidacy_claim_date': _candidacyClaimDate?.toUtc().toIso8601String(),
        'candidacy_final_date': _candidacyFinalDate?.toUtc().toIso8601String(),
      };

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
    return '${NepaliDateFormat('MMM dd, yyyy  hh:mm a').format(dt.toNepaliDateTime())} (BS)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.edit_calendar_rounded, color: AppColors.primaryLight, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Edit Election & Schedule', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          Text('Manage election details and timetable', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => context.pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Election Title *',
                            prefixIcon: Icon(Icons.title_rounded, size: 18),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _descController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Section 1: Election Schedule (Voting)
                        _buildSectionHeader('🗳️ Election Schedule (Voting)'),
                        const SizedBox(height: 8),
                        _buildDateRow(
                          icon: Icons.how_to_vote_rounded,
                          color: AppColors.stateVoting,
                          label: 'Voting Start Date',
                          subtitle: 'State → voting_open 🗳️',
                          value: _votingStartAt,
                          onTap: () => _pickDateTime('Voting Opens', _votingStartAt, (d) => setState(() => _votingStartAt = d)),
                          onClear: () => setState(() => _votingStartAt = null),
                        ),
                        const SizedBox(height: 8),
                        _buildDateRow(
                          icon: Icons.lock_outline_rounded,
                          color: AppColors.error,
                          label: 'Voting End Date',
                          subtitle: 'State → voting_closed 🔒 + auto-tally',
                          value: _votingEndAt,
                          onTap: () => _pickDateTime('Voting Closes', _votingEndAt, (d) => setState(() => _votingEndAt = d)),
                          onClear: () => setState(() => _votingEndAt = null),
                        ),
                        const SizedBox(height: 18),

                        // Section 2: Voter List Schedule
                        _buildSectionHeader('👥 Voter List Schedule'),
                        const SizedBox(height: 8),
                        _buildDateRow(
                          icon: Icons.people_outline_rounded,
                          color: const Color(0xFF3B82F6),
                          label: 'First Voter List Publication',
                          subtitle: 'Initial roll published for verification',
                          value: _firstVoterListDate,
                          onTap: () => _pickDateTime('First Voter List', _firstVoterListDate, (d) => setState(() => _firstVoterListDate = d)),
                          onClear: () => setState(() => _firstVoterListDate = null),
                        ),
                        const SizedBox(height: 8),
                        _buildDateRow(
                          icon: Icons.rule_folder_outlined,
                          color: const Color(0xFFF59E0B),
                          label: 'Voter List Claim & Objection Deadline',
                          subtitle: 'Voter claim/objection period ends',
                          value: _voterListClaimDate,
                          onTap: () => _pickDateTime('Voter List Claim', _voterListClaimDate, (d) => setState(() => _voterListClaimDate = d)),
                          onClear: () => setState(() => _voterListClaimDate = null),
                        ),
                        const SizedBox(height: 8),
                        _buildDateRow(
                          icon: Icons.verified_user_outlined,
                          color: const Color(0xFF10B981),
                          label: 'Final Voter List Publication',
                          subtitle: 'Final frozen voter list published',
                          value: _finalVoterListDate,
                          onTap: () => _pickDateTime('Final Voter List', _finalVoterListDate, (d) => setState(() => _finalVoterListDate = d)),
                          onClear: () => setState(() => _finalVoterListDate = null),
                        ),
                        const SizedBox(height: 18),

                        // Section 3: Candidacy Schedule
                        _buildSectionHeader('📋 Candidacy Schedule'),
                        const SizedBox(height: 8),
                        _buildDateRow(
                          icon: Icons.person_add_alt_1_outlined,
                          color: AppColors.stateNominations,
                          label: 'Candidacy Start (Nominations Open)',
                          subtitle: 'State → nominations_open',
                          value: _nominationOpenAt,
                          onTap: () => _pickDateTime('Nominations Open', _nominationOpenAt, (d) => setState(() => _nominationOpenAt = d)),
                          onClear: () => setState(() => _nominationOpenAt = null),
                        ),
                        const SizedBox(height: 8),
                        _buildDateRow(
                          icon: Icons.lock_clock_outlined,
                          color: AppColors.warning,
                          label: 'Candidacy End (Nominations Close)',
                          subtitle: 'State → nominations_closed',
                          value: _nominationCloseAt,
                          onTap: () => _pickDateTime('Nominations Close', _nominationCloseAt, (d) => setState(() => _nominationCloseAt = d)),
                          onClear: () => setState(() => _nominationCloseAt = null),
                        ),
                        const SizedBox(height: 8),
                        _buildDateRow(
                          icon: Icons.rate_review_outlined,
                          color: const Color(0xFF8B5CF6),
                          label: 'Candidacy Claim & Review Deadline',
                          subtitle: 'Objection and claim review deadline',
                          value: _candidacyClaimDate,
                          onTap: () => _pickDateTime('Candidacy Claim', _candidacyClaimDate, (d) => setState(() => _candidacyClaimDate = d)),
                          onClear: () => setState(() => _candidacyClaimDate = null),
                        ),
                        const SizedBox(height: 8),
                        _buildDateRow(
                          icon: Icons.how_to_reg_rounded,
                          color: const Color(0xFF059669),
                          label: 'Final Candidate List Publication',
                          subtitle: 'Final official list of approved candidates',
                          value: _candidacyFinalDate,
                          onTap: () => _pickDateTime('Final Candidate List', _candidacyFinalDate, (d) => setState(() => _candidacyFinalDate = d)),
                          onClear: () => setState(() => _candidacyFinalDate = null),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),

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
                        label: 'Save Changes',
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

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
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
