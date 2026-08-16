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
  late TextEditingController _resultOrderController;
  late TextEditingController _chargeController;
  late String _votingMethod;
  late String _bgColor;
  bool _isLoading = false;

  static const List<Map<String, dynamic>> _presetColors = [
    {'hex': '#563D7C', 'color': Color(0xFF563D7C), 'name': 'Royal Purple'},
    {'hex': '#4338CA', 'color': Color(0xFF4338CA), 'name': 'Indigo'},
    {'hex': '#2563EB', 'color': Color(0xFF2563EB), 'name': 'Blue'},
    {'hex': '#0D9488', 'color': Color(0xFF0D9488), 'name': 'Teal'},
    {'hex': '#059669', 'color': Color(0xFF059669), 'name': 'Emerald'},
    {'hex': '#D97706', 'color': Color(0xFFD97706), 'name': 'Amber'},
    {'hex': '#E11D48', 'color': Color(0xFFE11D48), 'name': 'Rose'},
    {'hex': '#1E293B', 'color': Color(0xFF1E293B), 'name': 'Slate'},
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.position.title);
    _seatsController = TextEditingController(text: widget.position.seatsAvailable.toString());
    _resultOrderController = TextEditingController(text: widget.position.resultOrder.toString());
    _chargeController = TextEditingController(text: widget.position.nomineeCharge.toStringAsFixed(2));
    _votingMethod = widget.position.votingMethod;
    _bgColor = widget.position.bgColor.isNotEmpty ? widget.position.bgColor : '#563D7C';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _seatsController.dispose();
    _resultOrderController.dispose();
    _chargeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final dio = ref.read(apiClientProvider);
      await dio.patch(
        '${ApiConstants.electionPositions(widget.electionId)}${widget.position.id}/',
        data: {
          'title': _titleController.text.trim(),
          'seats_available': int.parse(_seatsController.text.trim()),
          'result_order': int.tryParse(_resultOrderController.text.trim()) ?? 0,
          'nominee_charge': double.tryParse(_chargeController.text.trim()) ?? 0.0,
          'bg_color': _bgColor,
          'voting_method': _votingMethod,
        },
      );
      ref.invalidate(electionProvider(widget.electionId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text('Designation "${_titleController.text.trim()}" updated successfully!'),
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
            content: Text('Failed to update designation: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 850),
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
                    child: const Icon(Icons.edit_note_rounded, color: AppColors.primaryLight, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Designation (पद सम्पादन)',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Update seat capacities, ballot order, fee, and theme identifier.',
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
                      // Designation Title
                      TextFormField(
                        controller: _titleController,
                        decoration: _dec(
                          'Designation Title *',
                          hint: 'e.g. President, General Secretary',
                          prefix: const Icon(Icons.badge_outlined),
                          isDark: isDark,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Seats & Result Order Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _seatsController,
                              decoration: _dec(
                                'Max Seats *',
                                hint: '1',
                                helper: 'Winning seat capacity',
                                prefix: const Icon(Icons.event_seat_rounded),
                                isDark: isDark,
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                final n = int.tryParse(v ?? '');
                                if (n == null || n <= 0) return 'Must be >= 1';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextFormField(
                              controller: _resultOrderController,
                              decoration: _dec(
                                'Ballot Rank Order',
                                hint: '0',
                                helper: 'Lower numbers appear higher',
                                prefix: const Icon(Icons.format_list_numbered_rounded),
                                isDark: isDark,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Nominee Fee & Voting Method Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _chargeController,
                              decoration: _dec(
                                'Nominee Fee (NPR)',
                                hint: '0.00',
                                prefix: const Icon(Icons.payments_outlined),
                                isDark: isDark,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _votingMethod,
                              decoration: _dec(
                                'Voting Method',
                                prefix: const Icon(Icons.how_to_vote_outlined),
                                isDark: isDark,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'fptp', child: Text('First-Past-The-Post')),
                                DropdownMenuItem(value: 'multi_choice', child: Text('Block Voting (Multi)')),
                                DropdownMenuItem(value: 'ranked_choice', child: Text('Ranked Choice (STV)')),
                                DropdownMenuItem(value: 'approval', child: Text('Approval Voting')),
                                DropdownMenuItem(value: 'weighted', child: Text('Weighted Voting')),
                                DropdownMenuItem(value: 'proxy', child: Text('Proxy Voting')),
                                DropdownMenuItem(value: 'yes_no', child: Text('Yes/No (Referendum)')),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _votingMethod = v);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Color Swatches Section
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Designation Theme Color (रङ पहिचान)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _presetColors.map((item) {
                              final hex = item['hex'] as String;
                              final color = item['color'] as Color;
                              final isSelected = _bgColor.toLowerCase() == hex.toLowerCase();

                              return InkWell(
                                onTap: () => setState(() => _bgColor = hex),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? (isDark ? Colors.white : Colors.black87) : Colors.transparent,
                                      width: isSelected ? 3 : 0,
                                    ),
                                    boxShadow: [
                                      if (isSelected)
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.5),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                    ],
                                  ),
                                  child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                                ),
                              );
                            }).toList(),
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
                    label: 'Save Changes',
                    icon: Icons.check_circle_outline_rounded,
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
}
