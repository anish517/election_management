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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voting End date must be after Voting Start date.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_nominationOpenAt != null && _nominationCloseAt != null && _nominationCloseAt!.isBefore(_nominationOpenAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nomination Close date must be after Nomination Open date.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text('Election timetable updated! Automated lifecycle active.'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update election: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Not set — tap to configure';
    return '${NepaliDateFormat('MMM dd, yyyy  hh:mm a').format(dt.toNepaliDateTime())} (BS)';
  }

  InputDecoration _dec(
    String label, {
    String? hint,
    Widget? prefix,
    String? helper,
    bool isDark = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      prefixIcon: prefix,
      filled: true,
      fillColor: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.5) : const Color(0xFFF9FAFB),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660, maxHeight: 860),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dialog Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit_calendar_rounded, color: AppColors.primaryLight, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Election & Timetable (निर्वाचन कार्यतालिका)',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Configure election title, description, and automated schedule lifecycle (BS calendar).',
                          style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Form Scrollable Body
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      // Title & Description
                      TextFormField(
                        controller: _titleController,
                        decoration: _dec(
                          'Election Title *',
                          hint: 'e.g. 5th Annual General Committee Election',
                          prefix: const Icon(Icons.title_rounded),
                          isDark: isDark,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Election title is required' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descController,
                        decoration: _dec(
                          'Election Description / Context',
                          hint: 'Official purpose and scope...',
                          prefix: const Icon(Icons.notes_rounded),
                          isDark: isDark,
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 20),

                      // Section 1: Voter List Schedule (Step 1)
                      _buildScheduleGroupCard(
                        title: '1. Voter Roll Schedule (मतदाता नामावली कार्यतालिका)',
                        subtitle: 'Publication and claims scrutiny milestones',
                        icon: Icons.people_outline_rounded,
                        isDark: isDark,
                        children: [
                          _buildDateRow(
                            icon: Icons.people_outline_rounded,
                            color: const Color(0xFF3B82F6),
                            label: 'First Voter List Publication',
                            subtitle: 'Preliminary roll published for scrutiny',
                            value: _firstVoterListDate,
                            onTap: () => _pickDateTime('First Voter List', _firstVoterListDate, (d) => setState(() => _firstVoterListDate = d)),
                            onClear: () => setState(() => _firstVoterListDate = null),
                            isDark: isDark,
                          ),
                          const SizedBox(height: 10),
                          _buildDateRow(
                            icon: Icons.rule_folder_outlined,
                            color: const Color(0xFFF59E0B),
                            label: 'Voter Claims & Objection Deadline',
                            subtitle: 'Voter roll objections period ends',
                            value: _voterListClaimDate,
                            onTap: () => _pickDateTime('Voter List Claim', _voterListClaimDate, (d) => setState(() => _voterListClaimDate = d)),
                            onClear: () => setState(() => _voterListClaimDate = null),
                            isDark: isDark,
                          ),
                          const SizedBox(height: 10),
                          _buildDateRow(
                            icon: Icons.verified_user_outlined,
                            color: const Color(0xFF10B981),
                            label: 'Final Voter List Publication',
                            subtitle: 'Official frozen voter roll finalized',
                            value: _finalVoterListDate,
                            onTap: () => _pickDateTime('Final Voter List', _finalVoterListDate, (d) => setState(() => _finalVoterListDate = d)),
                            onClear: () => setState(() => _finalVoterListDate = null),
                            isDark: isDark,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Section 2: Candidacy Schedule (Step 2)
                      _buildScheduleGroupCard(
                        title: '2. Candidacy Schedule (उम्मेदवारी कार्यतालिका)',
                        subtitle: 'Nomination filings, objections, and final slate',
                        icon: Icons.badge_outlined,
                        isDark: isDark,
                        children: [
                          _buildDateRow(
                            icon: Icons.person_add_alt_1_outlined,
                            color: const Color(0xFF8B5CF6),
                            label: 'Candidacy Start (Nominations Open)',
                            subtitle: 'Digital candidacy submission window opens',
                            value: _nominationOpenAt,
                            onTap: () => _pickDateTime('Nominations Open', _nominationOpenAt, (d) => setState(() => _nominationOpenAt = d)),
                            onClear: () => setState(() => _nominationOpenAt = null),
                            isDark: isDark,
                          ),
                          const SizedBox(height: 10),
                          _buildDateRow(
                            icon: Icons.lock_clock_outlined,
                            color: const Color(0xFFD97706),
                            label: 'Candidacy End (Nominations Close)',
                            subtitle: 'Nomination filing window closes',
                            value: _nominationCloseAt,
                            onTap: () => _pickDateTime('Nominations Close', _nominationCloseAt, (d) => setState(() => _nominationCloseAt = d)),
                            onClear: () => setState(() => _nominationCloseAt = null),
                            isDark: isDark,
                          ),
                          const SizedBox(height: 10),
                          _buildDateRow(
                            icon: Icons.rate_review_outlined,
                            color: const Color(0xFFE11D48),
                            label: 'Candidacy Claim & Objection Deadline',
                            subtitle: 'Candidate qualification review cutoff',
                            value: _candidacyClaimDate,
                            onTap: () => _pickDateTime('Candidacy Claim', _candidacyClaimDate, (d) => setState(() => _candidacyClaimDate = d)),
                            onClear: () => setState(() => _candidacyClaimDate = null),
                            isDark: isDark,
                          ),
                          const SizedBox(height: 10),
                          _buildDateRow(
                            icon: Icons.how_to_reg_rounded,
                            color: const Color(0xFF059669),
                            label: 'Final Candidate List Publication',
                            subtitle: 'Approved candidate ballot slate locked',
                            value: _candidacyFinalDate,
                            onTap: () => _pickDateTime('Final Candidate List', _candidacyFinalDate, (d) => setState(() => _candidacyFinalDate = d)),
                            onClear: () => setState(() => _candidacyFinalDate = null),
                            isDark: isDark,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Section 3: Voting & Polling Schedule (Step 3)
                      _buildScheduleGroupCard(
                        title: '3. Voting & Polling Schedule (मतदान कार्यतालिका)',
                        subtitle: 'Official digital ballot casting window and auto-tally',
                        icon: Icons.how_to_vote_rounded,
                        isDark: isDark,
                        children: [
                          _buildDateRow(
                            icon: Icons.how_to_vote_rounded,
                            color: Colors.green,
                            label: 'Voting Start Date & Time',
                            subtitle: 'Voters can begin casting ballots',
                            value: _votingStartAt,
                            onTap: () => _pickDateTime('Voting Opens', _votingStartAt, (d) => setState(() => _votingStartAt = d)),
                            onClear: () => setState(() => _votingStartAt = null),
                            isDark: isDark,
                          ),
                          const SizedBox(height: 10),
                          _buildDateRow(
                            icon: Icons.lock_outline_rounded,
                            color: Colors.redAccent,
                            label: 'Voting End Date & Time',
                            subtitle: 'Ballot casting terminates and auto-tally commences',
                            value: _votingEndAt,
                            onTap: () => _pickDateTime('Voting Closes', _votingEndAt, (d) => setState(() => _votingEndAt = d)),
                            onClear: () => setState(() => _votingEndAt = null),
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isLoading ? null : () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 14),
                  LoadingButton(
                    isLoading: _isLoading,
                    label: 'Save Timetable',
                    icon: Icons.save_rounded,
                    onPressed: _submit,
                    fullWidth: false,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleGroupCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Material(
      color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFFAFAFA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primaryLight, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(subtitle, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
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
    required bool isDark,
  }) {
    final isSet = value != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSet
              ? color.withValues(alpha: isDark ? 0.12 : 0.06)
              : (isDark ? AppColors.surfaceVariant : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSet ? color.withValues(alpha: 0.4) : (isDark ? Colors.white12 : Colors.grey.shade300),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    isSet ? _formatDate(value) : subtitle,
                    style: TextStyle(
                      color: isSet ? color : (isDark ? Colors.white54 : Colors.grey.shade600),
                      fontSize: 11,
                      fontWeight: isSet ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (isSet)
              IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.grey),
                tooltip: 'Clear Date',
                onPressed: onClear,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else
              const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}
