import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loading_button.dart';

// ---------------------------------------------------------------------------
// Paid status choices
// ---------------------------------------------------------------------------
const _paidOptions = [
  DropdownMenuItem<bool>(value: false, child: Text('Free — No charge for candidacy')),
  DropdownMenuItem<bool>(value: true, child: Text('Paid — Nominee charged a fee')),
];

// ---------------------------------------------------------------------------
// Date/time picker helper
// ---------------------------------------------------------------------------
Future<DateTime?> _pickNepaliDateTime(BuildContext context, DateTime? current) async {
  NepaliDateTime initial = (current ?? DateTime.now()).toNepaliDateTime();
  final date = await showMaterialDatePicker(
    context: context,
    initialDate: initial,
    firstDate: NepaliDateTime(2070, 1, 1),
    lastDate: NepaliDateTime(2100, 12, 30),
  );
  if (date == null) return null;
  if (!context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
  );
  if (time == null) return null;
  final ndt = NepaliDateTime(date.year, date.month, date.day, time.hour, time.minute);
  return ndt.toDateTime();
}

String _formatNepali(DateTime? dt) {
  if (dt == null) return 'Select';
  return NepaliDateFormat('EEE, MMM d yyyy  h:mm a').format(dt.toNepaliDateTime());
}

// ---------------------------------------------------------------------------
// Compact date picker tile
// ---------------------------------------------------------------------------
class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? value;
  final bool required;
  final VoidCallback onTap;

  const _DateTile({required this.label, required this.value, required this.onTap, this.required = false});

  @override
  Widget build(BuildContext context) {
    final hasVal = value != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: hasVal
              ? AppColors.primary.withValues(alpha: 0.07)
              : Theme.of(context).inputDecorationTheme.fillColor ?? Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasVal ? AppColors.primaryLight.withValues(alpha: 0.5) : Theme.of(context).dividerColor,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 16,
              color: hasVal ? AppColors.primaryLight : AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    required ? '$label *' : label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatNepali(value),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: hasVal ? AppColors.primaryLight : AppColors.textMuted,
                          fontWeight: hasVal ? FontWeight.w600 : FontWeight.normal,
                        ),
                  ),
                ],
              ),
            ),
            if (hasVal)
              Icon(Icons.check_circle_rounded, color: AppColors.primaryLight, size: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2-column date row
// ---------------------------------------------------------------------------
Widget _dateRow(BuildContext context, String labelA, DateTime? valA, VoidCallback onA,
    String labelB, DateTime? valB, VoidCallback onB, {bool reqA = false, bool reqB = false}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _DateTile(label: labelA, value: valA, onTap: onA, required: reqA)),
      const SizedBox(width: 10),
      Expanded(child: _DateTile(label: labelB, value: valB, onTap: onB, required: reqB)),
    ],
  );
}

// ---------------------------------------------------------------------------
// Section header card
// ---------------------------------------------------------------------------
Widget _sectionCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required List<Widget> children}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, color: AppColors.primaryLight, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.surfaceVariant.withValues(alpha: 0.5)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Create Election Screen
// ---------------------------------------------------------------------------
class CreateElectionScreen extends ConsumerStatefulWidget {
  const CreateElectionScreen({super.key});

  @override
  ConsumerState<CreateElectionScreen> createState() => _CreateElectionScreenState();
}

class _CreateElectionScreenState extends ConsumerState<CreateElectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollCtrl = ScrollController();

  // --- Election Info ---
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _prefixCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  String _logoUrl = '';
  String _primaryColor = '#6C5CE7';
  String _secondaryColor = '#A29BFE';
  bool _uploading = false;

  // --- Election Schedule ---
  DateTime? _votingStart;
  DateTime? _votingEnd;

  // --- Voter List Schedule ---
  DateTime? _firstVoterList;
  DateTime? _voterListClaim;
  DateTime? _finalVoterList;

  // --- Candidacy Schedule ---
  DateTime? _candidacyStart;
  DateTime? _candidacyEnd;
  DateTime? _candidacyClaim;
  DateTime? _candidacyFinal;

  // --- Payment ---
  bool _isPaid = false;
  final _chargeCtrl = TextEditingController(text: '0');

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _prefixCtrl.dispose();
    _contactCtrl.dispose();
    _chargeCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // --- Upload logo ---
  Future<void> _uploadLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'svg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;
    setState(() => _uploading = true);
    try {
      final dio = ref.read(apiClientProvider);
      final bytes = result.files.first.bytes!;
      final name = result.files.first.name;
      final resp = await dio.post(
        ApiConstants.fileUpload,
        data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: name)}),
      );
      final url = resp.data['url'] as String?;
      if (url != null) { setState(() => _logoUrl = url); }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logo upload failed.')));
      }
    } finally {
      if (mounted) { setState(() => _uploading = false); }
    }
  }

  Future<void> _pick(DateTime? current, void Function(DateTime) onSet) async {
    final dt = await _pickNepaliDateTime(context, current);
    if (dt != null && mounted) { setState(() => onSet(dt)); }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_votingStart == null || _votingEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Election Start and End dates are required.')));
      return;
    }
    try {
      await ref.read(createElectionProvider.notifier).createElection(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        prefix: _prefixCtrl.text.trim(),
        logoUrl: _logoUrl,
        contactNumber: _contactCtrl.text.trim(),
        primaryColor: _primaryColor,
        secondaryColor: _secondaryColor,
        votingStartAt: _votingStart,
        votingEndAt: _votingEnd,
        firstVoterListDate: _firstVoterList,
        voterListClaimDate: _voterListClaim,
        finalVoterListDate: _finalVoterList,
        nominationOpenAt: _candidacyStart,
        nominationCloseAt: _candidacyEnd,
        candidacyClaimDate: _candidacyClaim,
        candidacyFinalDate: _candidacyFinal,
        isPaidCandidacy: _isPaid,
        nomineeCharge: double.tryParse(_chargeCtrl.text) ?? 0,
      );
      if (mounted) {
        if (context.canPop()) { context.pop(); }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 10),
              Text('Election created as Draft!', style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(24),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade600),
        );
      }
    }
  }

  InputDecoration _dec(String label, {String? hint, Widget? prefix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  // --- Color picker tile ---
  Widget _colorTile(String label, String color, void Function(String) onChange) {
    return GestureDetector(
      onTap: () async {
        final ctrl = TextEditingController(text: color);
        final result = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(label),
            content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Hex color (e.g. #6C5CE7)', prefixIcon: Icon(Icons.colorize)),
              autofocus: true,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Apply')),
            ],
          ),
        );
        if (result != null && result.isNotEmpty) { setState(() => onChange(result)); }
      },
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: _hexToColor(color),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.colorize, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Color _hexToColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createElectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Election'),
        centerTitle: false,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: LoadingButton(
              isLoading: state.isLoading,
              label: 'Create Draft',
              icon: Icons.save_rounded,
              onPressed: _submit,
              fullWidth: false,
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Form(
            key: _formKey,
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
              children: [

                // ══════════════════════════════════════════════════════════
                // 1. ELECTION INFORMATION
                // ══════════════════════════════════════════════════════════
                _sectionCard(context,
                  title: 'Election Information',
                  subtitle: 'Basic identity and branding of this election',
                  icon: Icons.how_to_vote_rounded,
                  children: [
                    // Title + Prefix
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _titleCtrl,
                            decoration: _dec('Election Title *', hint: 'Enter election title', prefix: const Icon(Icons.how_to_vote_outlined)),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _prefixCtrl,
                            decoration: _dec('Prefix *', hint: 'e.g. ELEC', prefix: const Icon(Icons.label_outline)),
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 10,
                            buildCounter: (_, {required currentLength, required isFocused, required maxLength}) => null,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Description
                    TextFormField(
                      controller: _descCtrl,
                      decoration: _dec('Description', hint: 'Brief description of this election', prefix: const Icon(Icons.description_outlined)),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 14),

                    // Contact
                    TextFormField(
                      controller: _contactCtrl,
                      decoration: _dec('Contact Number *', hint: 'Enter contact number', prefix: const Icon(Icons.phone_outlined)),
                      keyboardType: TextInputType.phone,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 14),

                    // Logo
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Logo *', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _uploading ? null : _uploadLogo,
                          child: Container(
                            height: 110,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Theme.of(context).dividerColor, width: 1.5),
                              image: _logoUrl.isNotEmpty ? DecorationImage(image: NetworkImage(_logoUrl), fit: BoxFit.contain) : null,
                            ),
                            child: _uploading
                                ? const Center(child: CircularProgressIndicator())
                                : _logoUrl.isEmpty
                                    ? Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add_photo_alternate_outlined, color: AppColors.textMuted, size: 30),
                                          const SizedBox(height: 6),
                                          Text('Tap to upload logo', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                                          Text('Max 2MB · jpeg, png, jpg, gif, svg', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                                        ],
                                      )
                                    : Align(
                                        alignment: Alignment.bottomRight,
                                        child: Container(
                                          margin: const EdgeInsets.all(8),
                                          padding: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                          child: const Icon(Icons.edit, color: Colors.white, size: 14),
                                        ),
                                      ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Colors
                    Row(
                      children: [
                        Expanded(child: _colorTile('Primary Color', _primaryColor, (c) => _primaryColor = c)),
                        const SizedBox(width: 12),
                        Expanded(child: _colorTile('Secondary Color', _secondaryColor, (c) => _secondaryColor = c)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Tap a color swatch to enter a hex value.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                  ],
                ),

                // ══════════════════════════════════════════════════════════
                // 2. ELECTION SCHEDULE
                // ══════════════════════════════════════════════════════════
                _sectionCard(context,
                  title: 'Election Schedule',
                  subtitle: 'Voting start and end dates (required)',
                  icon: Icons.schedule_rounded,
                  children: [
                    _dateRow(
                      context,
                      'Election Start Date *', _votingStart, () => _pick(_votingStart, (d) => _votingStart = d),
                      'Election End Date *', _votingEnd, () => _pick(_votingEnd, (d) => _votingEnd = d),
                      reqA: true, reqB: true,
                    ),
                  ],
                ),

                // ══════════════════════════════════════════════════════════
                // 3. VOTER LIST SCHEDULE
                // ══════════════════════════════════════════════════════════
                _sectionCard(context,
                  title: 'Voter List Schedule',
                  subtitle: 'Dates for voter list publication, claims, and finalization',
                  icon: Icons.people_rounded,
                  children: [
                    _dateRow(
                      context,
                      'First Voter List', _firstVoterList, () => _pick(_firstVoterList, (d) => _firstVoterList = d),
                      'Voter List Claim', _voterListClaim, () => _pick(_voterListClaim, (d) => _voterListClaim = d),
                    ),
                    const SizedBox(height: 10),
                    _DateTile(
                      label: 'Final Voter List',
                      value: _finalVoterList,
                      onTap: () => _pick(_finalVoterList, (d) => _finalVoterList = d),
                    ),
                  ],
                ),

                // ══════════════════════════════════════════════════════════
                // 4. CANDIDACY SCHEDULE
                // ══════════════════════════════════════════════════════════
                _sectionCard(context,
                  title: 'Candidacy Schedule',
                  subtitle: 'Nomination, claim, and finalization dates',
                  icon: Icons.assignment_ind_rounded,
                  children: [
                    _dateRow(
                      context,
                      'Candidacy Start', _candidacyStart, () => _pick(_candidacyStart, (d) => _candidacyStart = d),
                      'Candidacy End', _candidacyEnd, () => _pick(_candidacyEnd, (d) => _candidacyEnd = d),
                    ),
                    const SizedBox(height: 10),
                    _dateRow(
                      context,
                      'Candidacy Claim', _candidacyClaim, () => _pick(_candidacyClaim, (d) => _candidacyClaim = d),
                      'Candidacy Final', _candidacyFinal, () => _pick(_candidacyFinal, (d) => _candidacyFinal = d),
                    ),
                  ],
                ),

                // ══════════════════════════════════════════════════════════
                // 5. PAID STATUS
                // ══════════════════════════════════════════════════════════
                _sectionCard(context,
                  title: 'Candidacy Payment',
                  subtitle: 'Only if candidacy nominees are charged a fee',
                  icon: Icons.payments_rounded,
                  children: [
                    DropdownButtonFormField<bool>(
                      initialValue: _isPaid,
                      decoration: _dec('Paid Status *', prefix: const Icon(Icons.monetization_on_outlined)),
                      items: _paidOptions,
                      onChanged: (val) => setState(() => _isPaid = val ?? false),
                    ),
                    if (_isPaid) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _chargeCtrl,
                        decoration: _dec('Nominee Charge (NPR) *', hint: 'e.g. 500', prefix: const Icon(Icons.currency_rupee_outlined)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (!_isPaid) return null;
                          if (v == null || v.trim().isEmpty) return 'Required when paid';
                          if (double.tryParse(v) == null) return 'Enter a valid amount';
                          return null;
                        },
                      ),
                    ],
                  ],
                ),

                // Submit
                const SizedBox(height: 8),
                SizedBox(
                  height: 54,
                  child: LoadingButton(
                    isLoading: state.isLoading,
                    label: 'Create Election as Draft',
                    icon: Icons.how_to_vote_rounded,
                    onPressed: _submit,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Back to Elections'),
                    onPressed: () {
                      if (context.canPop()) { context.pop(); } else { context.go('/admin/elections'); }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
