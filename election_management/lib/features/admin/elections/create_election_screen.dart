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
// Nepali Date/time picker helper
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
  if (dt == null) return 'Select Date & Time';
  final bsStr = NepaliDateFormat('MMM d, yyyy • h:mm a').format(dt.toNepaliDateTime());
  return '$bsStr (BS)';
}

// Preset theme colors for quick election branding
const _presetColors = [
  {'name': 'Indigo', 'primary': '#4F46E5', 'secondary': '#818CF8'},
  {'name': 'Emerald', 'primary': '#059669', 'secondary': '#34D399'},
  {'name': 'Crimson', 'primary': '#DC2626', 'secondary': '#F87171'},
  {'name': 'Ocean', 'primary': '#0284C7', 'secondary': '#38BDF8'},
  {'name': 'Amber', 'primary': '#D97706', 'secondary': '#FBBF24'},
  {'name': 'Purple', 'primary': '#7C3AED', 'secondary': '#A78BFA'},
];

// ---------------------------------------------------------------------------
// Professional Compact Date Tile
// ---------------------------------------------------------------------------
class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? value;
  final bool required;
  final VoidCallback onTap;

  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasVal = value != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hasVal
              ? (isDark ? AppColors.primary.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.05))
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasVal
                ? AppColors.primaryLight.withValues(alpha: 0.6)
                : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
            width: hasVal ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: hasVal ? AppColors.primary : (isDark ? Colors.white10 : Colors.grey.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.calendar_today_rounded,
                size: 15,
                color: hasVal ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.grey.shade800,
                        ),
                      ),
                      if (required) ...[
                        const SizedBox(width: 4),
                        const Text('*', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatNepali(value),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: hasVal ? FontWeight.w600 : FontWeight.normal,
                      color: hasVal
                          ? (isDark ? AppColors.primaryLight : AppColors.primary)
                          : (isDark ? Colors.white38 : Colors.grey.shade500),
                    ),
                  ),
                ],
              ),
            ),
            if (hasVal)
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18)
            else
              Icon(Icons.arrow_drop_down_rounded, color: isDark ? Colors.white38 : Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section Card Container
// ---------------------------------------------------------------------------
Widget _sectionCard(
  BuildContext context, {
  required String step,
  required String title,
  required String subtitle,
  required IconData icon,
  required List<Widget> children,
  Widget? trailing,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Material(
      color: isDark ? AppColors.surface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
        ),
      ),
      elevation: isDark ? 0 : 1,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  step,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.white60 : Colors.grey.shade600,
                            fontSize: 12,
                          ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    ),
  ),
);
}

// ---------------------------------------------------------------------------
// Create Election Screen Implementation
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
  String _primaryColor = '#4F46E5';
  String _secondaryColor = '#818CF8';
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

  // --- Ballot & Voting Rules ---
  bool _isSecretBallot = true;
  bool _allowBoycott = true;

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
      if (url != null) {
        setState(() => _logoUrl = url);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo upload failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _pick(DateTime? current, void Function(DateTime) onSet) async {
    final dt = await _pickNepaliDateTime(context, current);
    if (dt != null && mounted) {
      setState(() => onSet(dt));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all required fields.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_votingStart == null || _votingEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Election Start and End dates are required.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_votingEnd!.isBefore(_votingStart!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voting End date must be after Voting Start date.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_candidacyStart != null && _candidacyEnd != null && _candidacyEnd!.isBefore(_candidacyStart!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nomination Close date must be after Nomination Open date.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_firstVoterList != null && _voterListClaim != null && _voterListClaim!.isBefore(_firstVoterList!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voter List Claim deadline must be after First Voter List date.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_voterListClaim != null && _finalVoterList != null && _finalVoterList!.isBefore(_voterListClaim!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Final Voter List date must be after Voter List Claim date.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        isSecretBallot: _isSecretBallot,
        allowBoycott: _allowBoycott,
        isPaidCandidacy: _isPaid,
        nomineeCharge: double.tryParse(_chargeCtrl.text) ?? 0,
      );
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/admin/elections');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 10),
                Text('Election created successfully as Draft!', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
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
          SnackBar(
            content: Text('Error creating election: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  InputDecoration _dec(String label, {String? hint, Widget? prefix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefix,
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
              label: 'Save Draft',
              icon: Icons.save_rounded,
              onPressed: _submit,
              fullWidth: false,
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Form(
            key: _formKey,
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              children: [
                // Top Welcome Card
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _hexToColor(_primaryColor),
                        _hexToColor(_secondaryColor),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _hexToColor(_primaryColor).withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.how_to_vote_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Election Setup Wizard',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Configure your election identity, timeline milestones, candidacy rules, and security.',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ══════════════════════════════════════════════════════════
                // 1. ELECTION INFORMATION
                // ══════════════════════════════════════════════════════════
                _sectionCard(
                  context,
                  step: 'STEP 1',
                  title: 'Election Identity & Branding',
                  subtitle: 'Basic name, code, contact information, and theme',
                  icon: Icons.badge_outlined,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _titleCtrl,
                            decoration: _dec('Election Title *', hint: 'e.g. Annual Executive Committee Election 2083', prefix: const Icon(Icons.how_to_vote_outlined)),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Election title is required' : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: _prefixCtrl,
                            decoration: _dec('Prefix Code *', hint: 'e.g. ELEC', prefix: const Icon(Icons.tag_rounded)),
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 10,
                            buildCounter: (_, {required currentLength, required isFocused, required maxLength}) => null,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _descCtrl,
                      decoration: _dec('Description', hint: 'Provide a brief overview of this election for members', prefix: const Icon(Icons.notes_rounded)),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _contactCtrl,
                      decoration: _dec('Official Helpline / Contact *', hint: 'e.g. +977-9841234567', prefix: const Icon(Icons.phone_outlined)),
                      keyboardType: TextInputType.phone,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Contact number is required' : null,
                    ),
                    const SizedBox(height: 20),

                    // Logo Upload Card
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.image_outlined, size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text('Official Election Emblem / Logo', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _uploading ? null : _uploadLogo,
                          child: Container(
                            height: 120,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _logoUrl.isNotEmpty ? AppColors.primary : (isDark ? Colors.white12 : Colors.grey.shade300),
                                width: 1.5,
                              ),
                            ),
                            child: _uploading
                                ? const Center(child: CircularProgressIndicator())
                                : _logoUrl.isEmpty
                                    ? Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.cloud_upload_outlined, color: AppColors.primary, size: 34),
                                          const SizedBox(height: 8),
                                          const Text('Click or tap to upload election logo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                          Text('Supported: JPG, PNG, SVG (Max 2MB)', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                                        ],
                                      )
                                    : Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Image.network(_logoUrl, fit: BoxFit.contain, height: 100),
                                          ),
                                          Positioned(
                                            right: 12,
                                            bottom: 12,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                                              child: const Row(
                                                children: [
                                                  Icon(Icons.edit, color: Colors.white, size: 12),
                                                  SizedBox(width: 4),
                                                  Text('Change', style: TextStyle(color: Colors.white, fontSize: 11)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Color Palettes
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Theme Palette Presets', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _presetColors.map((p) {
                            final isSelected = _primaryColor.toLowerCase() == p['primary']!.toLowerCase();
                            final pColor = _hexToColor(p['primary']!);
                            final sColor = _hexToColor(p['secondary']!);

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _primaryColor = p['primary']!;
                                  _secondaryColor = p['secondary']!;
                                });
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected ? pColor.withValues(alpha: 0.15) : (isDark ? Colors.white10 : Colors.grey.shade100),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected ? pColor : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(color: pColor, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(color: sColor, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      p['name']!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? pColor : (isDark ? Colors.white70 : Colors.black87),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ],
                ),

                // ══════════════════════════════════════════════════════════
                // 2. VOTER LIST SCHEDULE (Step 1)
                // ══════════════════════════════════════════════════════════
                _sectionCard(
                  context,
                  step: 'STEP 2',
                  title: 'Voter List Schedule (नामावली तालिका)',
                  subtitle: 'Initial publication, voter claims & objections, and certified final list',
                  icon: Icons.people_outline_rounded,
                  children: [
                    _DateTile(
                      label: '1. Preliminary Voter List Published (पहिलो नामावली)',
                      value: _firstVoterList,
                      onTap: () => _pick(_firstVoterList, (d) => _firstVoterList = d),
                    ),
                    const SizedBox(height: 10),
                    _DateTile(
                      label: '2. Voter List Claim Deadline (दाबी-विरोध अन्तिम मिति)',
                      value: _voterListClaim,
                      onTap: () => _pick(_voterListClaim, (d) => _voterListClaim = d),
                    ),
                    const SizedBox(height: 10),
                    _DateTile(
                      label: '3. Certified Final Voter List (अन्तिम नामावली प्रकाशन)',
                      value: _finalVoterList,
                      onTap: () => _pick(_finalVoterList, (d) => _finalVoterList = d),
                    ),
                  ],
                ),

                // ══════════════════════════════════════════════════════════
                // 3. CANDIDACY SCHEDULE (Step 2)
                // ══════════════════════════════════════════════════════════
                _sectionCard(
                  context,
                  step: 'STEP 3',
                  title: 'Candidacy & Nomination Schedule (उम्मेदवारी तालिका)',
                  subtitle: 'Filing period, scrutiny / objections, and certified candidate roster',
                  icon: Icons.assignment_ind_outlined,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _DateTile(
                            label: '1. Nominations Open',
                            value: _candidacyStart,
                            onTap: () => _pick(_candidacyStart, (d) => _candidacyStart = d),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DateTile(
                            label: '2. Nominations Close',
                            value: _candidacyEnd,
                            onTap: () => _pick(_candidacyEnd, (d) => _candidacyEnd = d),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _DateTile(
                            label: '3. Scrutiny / Objection Deadline',
                            value: _candidacyClaim,
                            onTap: () => _pick(_candidacyClaim, (d) => _candidacyClaim = d),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DateTile(
                            label: '4. Final Candidate List Published',
                            value: _candidacyFinal,
                            onTap: () => _pick(_candidacyFinal, (d) => _candidacyFinal = d),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // ══════════════════════════════════════════════════════════
                // 4. VOTING SCHEDULE (Step 3 - Core Required)
                // ══════════════════════════════════════════════════════════
                _sectionCard(
                  context,
                  step: 'STEP 4',
                  title: 'Voting & Polling Window (मतदान अवधि)',
                  subtitle: 'Official balloting start and end dates (Required)',
                  icon: Icons.how_to_vote_rounded,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _DateTile(
                            label: 'Polling Opens (मतदान सुरु)',
                            value: _votingStart,
                            onTap: () => _pick(_votingStart, (d) => _votingStart = d),
                            required: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DateTile(
                            label: 'Polling Closes (मतदान समाप्त)',
                            value: _votingEnd,
                            onTap: () => _pick(_votingEnd, (d) => _votingEnd = d),
                            required: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // ══════════════════════════════════════════════════════════
                // 5. PAID STATUS
                // ══════════════════════════════════════════════════════════
                _sectionCard(
                  context,
                  step: 'STEP 5',
                  title: 'Candidacy Nomination Fee',
                  subtitle: 'Configure whether candidates are charged a nomination fee',
                  icon: Icons.payments_outlined,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _isPaid = false),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: !_isPaid ? AppColors.primary.withValues(alpha: 0.1) : (isDark ? Colors.white10 : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: !_isPaid ? AppColors.primary : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(!_isPaid ? Icons.radio_button_checked : Icons.radio_button_off, color: !_isPaid ? AppColors.primary : Colors.grey),
                                  const SizedBox(width: 8),
                                  const Text('Free (निःशुल्क)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _isPaid = true),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _isPaid ? AppColors.primary.withValues(alpha: 0.1) : (isDark ? Colors.white10 : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _isPaid ? AppColors.primary : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(_isPaid ? Icons.radio_button_checked : Icons.radio_button_off, color: _isPaid ? AppColors.primary : Colors.grey),
                                  const SizedBox(width: 8),
                                  const Text('Paid Fee (शुल्क)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_isPaid) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _chargeCtrl,
                        decoration: _dec('Nominee Charge (NPR) *', hint: 'e.g. 500', prefix: const Icon(Icons.currency_rupee_rounded)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (!_isPaid) return null;
                          if (v == null || v.trim().isEmpty) return 'Fee is required when paid';
                          if (double.tryParse(v) == null) return 'Enter a valid amount';
                          return null;
                        },
                      ),
                    ],
                  ],
                ),

                // ══════════════════════════════════════════════════════════
                // 6. BALLOT & VOTING RULES
                // ══════════════════════════════════════════════════════════
                _sectionCard(
                  context,
                  step: 'STEP 6',
                  title: 'Electoral Privacy & Ballot Rules',
                  subtitle: 'Cryptographic secrecy, anonymity, and boycott configurations',
                  icon: Icons.security_rounded,
                  children: [
                    SwitchListTile(
                      value: _isSecretBallot,
                      onChanged: (val) => setState(() => _isSecretBallot = val),
                      title: const Text('Cryptographic Secret Ballot', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Strictly decouple voter identities from cast ballots with SHA-256 receipts'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(),
                    SwitchListTile(
                      value: _allowBoycott,
                      onChanged: (val) => setState(() => _allowBoycott = val),
                      title: const Text('Allow No Vote / Boycott (बहिष्कार)', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Allow voters to select "No Vote / Boycott" on candidate ballots'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),

                // Submit Button
                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
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
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/admin/elections');
                      }
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

