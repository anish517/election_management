import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/responsive_layout.dart';

class _QuotaDraft {
  final String? id;
  final TextEditingController nameCtrl;
  final TextEditingController seatsCtrl;
  final TextEditingController descCtrl;
  String status;

  _QuotaDraft({
    this.id,
    String initialName = '',
    int initialSeats = 1,
    String initialDesc = '',
    this.status = 'active',
  })  : nameCtrl = TextEditingController(text: initialName),
        seatsCtrl = TextEditingController(text: initialSeats.toString()),
        descCtrl = TextEditingController(text: initialDesc);

  void dispose() {
    nameCtrl.dispose();
    seatsCtrl.dispose();
    descCtrl.dispose();
  }
}

class CreateDesignationScreen extends ConsumerStatefulWidget {
  final String electionId;
  final PositionModel? positionToEdit;

  const CreateDesignationScreen({
    super.key,
    required this.electionId,
    this.positionToEdit,
  });

  @override
  ConsumerState<CreateDesignationScreen> createState() => _CreateDesignationScreenState();
}

class _CreateDesignationScreenState extends ConsumerState<CreateDesignationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _seatsController = TextEditingController(text: '1');
  final _chargeController = TextEditingController(text: '0.00');
  final _orderController = TextEditingController(text: '0');
  Color _selectedColor = const Color(0xFF563D7C);

  bool _enableQuotas = false;
  final List<_QuotaDraft> _quotas = [];
  bool _isSubmitting = false;

  bool get _isEditing => widget.positionToEdit != null;

  static const List<Color> _presetColors = [
    Color(0xFF563D7C), // Royal Purple
    Color(0xFF4338CA), // Indigo
    Color(0xFF2563EB), // Blue
    Color(0xFF0D9488), // Teal
    Color(0xFF059669), // Emerald
    Color(0xFFD97706), // Amber
    Color(0xFFE11D48), // Rose
    Color(0xFF1E293B), // Slate Dark
  ];

  static const List<Map<String, String>> _suggestedQuotas = [
    {'en': 'Female', 'ne': 'महिला'},
    {'en': 'Dalit', 'ne': 'दलित'},
    {'en': 'Janajati', 'ne': 'जनजाति'},
    {'en': 'Youth', 'ne': 'युवा'},
    {'en': 'Madhesi', 'ne': 'मधेशी'},
    {'en': 'Muslim', 'ne': 'मुस्लिम'},
    {'en': 'Khas Arya', 'ne': 'खस आर्य'},
    {'en': 'Tharu', 'ne': 'थारू'},
    {'en': 'Disability', 'ne': 'अपाङ्गता'},
    {'en': 'Open / General', 'ne': 'खुला'},
    {'en': 'Other', 'ne': 'अन्य'},
  ];

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final pos = widget.positionToEdit!;
      _titleController.text = pos.title;
      _seatsController.text = pos.seatsAvailable.toString();
      _chargeController.text = pos.nomineeCharge.toStringAsFixed(2);
      _orderController.text = pos.resultOrder.toString();
      try {
        final h = pos.bgColor.replaceAll('#', '');
        _selectedColor = Color(int.parse('FF$h', radix: 16));
      } catch (_) {
        _selectedColor = const Color(0xFF563D7C);
      }
      if (pos.quotas.isNotEmpty) {
        _enableQuotas = true;
        for (final q in pos.quotas) {
          _quotas.add(_QuotaDraft(
            id: q.id,
            initialName: q.name,
            initialSeats: q.seats,
            initialDesc: q.description,
            status: q.status,
          ));
        }
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _seatsController.dispose();
    _chargeController.dispose();
    _orderController.dispose();
    for (final q in _quotas) {
      q.dispose();
    }
    super.dispose();
  }

  void _pickColor() {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          title: const Text('Pick Designation Color', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: BlockPicker(
              pickerColor: _selectedColor,
              onColorChanged: (color) {
                setState(() => _selectedColor = color);
                Navigator.of(ctx).pop();
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _addQuotaRow() {
    setState(() {
      _quotas.add(_QuotaDraft());
    });
  }

  void _removeQuotaRow(int index) {
    setState(() {
      final removed = _quotas.removeAt(index);
      removed.dispose();
    });
  }

  int get _maxSeats => int.tryParse(_seatsController.text.trim()) ?? 1;

  int get _allocatedQuotaSeats => _quotas.fold<int>(
        0,
        (sum, q) => sum + (int.tryParse(q.seatsCtrl.text.trim()) ?? 0),
      );

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

    if (_enableQuotas) {
      if (_quotas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please add at least one quota row or disable Quota Reservations.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (_allocatedQuotaSeats > _maxSeats) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Total quota seats ($_allocatedQuotaSeats) exceed max designation seats ($_maxSeats).',
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final hexColor = '#${_selectedColor.toARGB32().toRadixString(16).substring(2, 8)}';

      final data = {
        'election': widget.electionId,
        'title': _titleController.text.trim(),
        'seats_available': _maxSeats,
        'voting_method': 'fptp',
        'max_votes_per_voter': _maxSeats,
        'nominee_charge': double.tryParse(_chargeController.text.trim()) ?? 0.0,
        'result_order': int.tryParse(_orderController.text.trim()) ?? 0,
        'bg_color': hexColor,
      };

      if (_isEditing) {
        final positionId = widget.positionToEdit!.id;
        await ref.read(publishElectionProvider.notifier).updatePosition(widget.electionId, positionId, data);

        if (_enableQuotas) {
          final existingIds = widget.positionToEdit!.quotas.map((q) => q.id).toSet();
          final keptIds = <String>{};

          for (final q in _quotas) {
            final qName = q.nameCtrl.text.trim();
            if (qName.isEmpty) continue;
            final qSeats = int.tryParse(q.seatsCtrl.text.trim()) ?? 1;
            final payload = {
              'position': positionId,
              'name': qName,
              'seats': qSeats,
              'status': q.status,
              'description': q.descCtrl.text.trim(),
            };

            if (q.id != null && existingIds.contains(q.id)) {
              keptIds.add(q.id!);
              await ref.read(quotaNotifierProvider.notifier).updateQuota(widget.electionId, q.id!, payload);
            } else {
              await ref.read(quotaNotifierProvider.notifier).addQuota(widget.electionId, payload);
            }
          }

          for (final oldId in existingIds) {
            if (!keptIds.contains(oldId)) {
              await ref.read(quotaNotifierProvider.notifier).deleteQuota(widget.electionId, oldId);
            }
          }
        } else {
          for (final q in widget.positionToEdit!.quotas) {
            await ref.read(quotaNotifierProvider.notifier).deleteQuota(widget.electionId, q.id);
          }
        }

        ref.invalidate(electionProvider(widget.electionId));
        ref.invalidate(quotasProvider(widget.electionId));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Text('Designation and quotas updated successfully!'),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        final createdPosition = await ref.read(publishElectionProvider.notifier).addPosition(data);
        final positionId = createdPosition['id'] as String?;

        if (_enableQuotas && positionId != null && positionId.isNotEmpty) {
          for (final q in _quotas) {
            final qName = q.nameCtrl.text.trim();
            if (qName.isEmpty) continue;
            final qSeats = int.tryParse(q.seatsCtrl.text.trim()) ?? 1;
            await ref.read(quotaNotifierProvider.notifier).addQuota(
              widget.electionId,
              {
                'position': positionId,
                'name': qName,
                'seats': qSeats,
                'status': q.status,
                'description': q.descCtrl.text.trim(),
              },
            );
          }
        }

        ref.invalidate(electionProvider(widget.electionId));
        ref.invalidate(quotasProvider(widget.electionId));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Text('Designation created successfully!'),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving designation: ${e.toString()}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Designation' : 'Create New Designation'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: LoadingButton(
              isLoading: _isSubmitting,
              label: _isEditing ? 'Save Changes' : 'Create Designation',
              icon: Icons.save_rounded,
              onPressed: _submit,
              fullWidth: false,
            ),
          ),
        ],
      ),
      body: ResponsivePageWrapper(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
            children: [
              // ══════════════════════════════════════════════════════════════
              // HERO BANNER
              // ══════════════════════════════════════════════════════════════
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4C1D95), Color(0xFF6D28D9), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6D28D9).withValues(alpha: 0.3),
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
                      child: const Icon(Icons.military_tech_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEditing ? 'Edit Designation (पद सम्पादन)' : 'Designation & Office Setup (पद तथा सिट व्यवस्थापन)',
                            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Configure institutional electoral office titles (e.g. President, Secretary, Member), available seat capacities, candidacy nomination charges, and reserved quotas.',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
              .animate()
              .fade(duration: 300.ms)
              .slideY(begin: -0.05, end: 0),
              const SizedBox(height: 24),

              // ══════════════════════════════════════════════════════════════
              // 1. DESIGNATION IDENTITY & SEAT CAPACITY
              // ══════════════════════════════════════════════════════════════
              _buildSectionCard(
                context,
                title: 'Designation Identity & Capacity (पद विवरण)',
                subtitle: 'Official title, maximum winning seats, and theme identifier',
                icon: Icons.badge_outlined,
                isDark: isDark,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _titleController,
                          decoration: _dec(
                            'Designation Title *',
                            hint: 'e.g. President, General Secretary, Board Member',
                            prefix: const Icon(Icons.military_tech_rounded),
                            isDark: isDark,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Designation title is required' : null,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _seatsController,
                          decoration: _dec(
                            'Max Seats *',
                            hint: '1',
                            prefix: const Icon(Icons.event_seat_rounded),
                            isDark: isDark,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          validator: (val) {
                            final n = int.tryParse(val ?? '');
                            if (n == null || n <= 0) return 'Must be >= 1';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Color Picker Section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Badge & Theme Color (रङ पहिचान)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Wrap(
                            spacing: 8,
                            children: _presetColors.map((color) {
                              final isSelected = _selectedColor.toARGB32() == color.toARGB32();
                              return InkWell(
                                onTap: () => setState(() => _selectedColor = color),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? Colors.white : Colors.transparent,
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
                                  child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(width: 14),
                          OutlinedButton.icon(
                            onPressed: _pickColor,
                            icon: const Icon(Icons.colorize_rounded, size: 16),
                            label: Text(
                              '#${_selectedColor.toARGB32().toRadixString(16).substring(2, 8).toUpperCase()}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ══════════════════════════════════════════════════════════════
              // 2. CANDIDACY CHARGE & BALLOT ORDER
              // ══════════════════════════════════════════════════════════════
              _buildSectionCard(
                context,
                title: 'Fee & Ballot Sequence (उम्मेदवारी शुल्क र क्रम)',
                subtitle: 'Candidacy registration fee and display order on voting ballots',
                icon: Icons.payments_outlined,
                isDark: isDark,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _chargeController,
                          decoration: _dec(
                            'Nominee Charge (NPR)',
                            hint: '0.00',
                            helper: 'Fee collected upon candidacy submission',
                            prefix: const Icon(Icons.payments_outlined),
                            isDark: isDark,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextFormField(
                          controller: _orderController,
                          decoration: _dec(
                            'Result & Ballot Order',
                            hint: '0',
                            helper: 'Lower numbers appear higher on ballot',
                            prefix: const Icon(Icons.format_list_numbered_rounded),
                            isDark: isDark,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ══════════════════════════════════════════════════════════════
              // 3. AFFIRMATIVE ACTION & QUOTA RESERVATION HUB
              // ══════════════════════════════════════════════════════════════
              Material(
                color: isDark ? AppColors.surface : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _enableQuotas
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200),
                  ),
                ),
                elevation: isDark ? 0 : 1,
                shadowColor: Colors.black.withValues(alpha: 0.04),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Quota Enable Switch Row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _enableQuotas
                                  ? AppColors.primary.withValues(alpha: 0.12)
                                  : (isDark ? Colors.white12 : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.pie_chart_rounded,
                              color: _enableQuotas ? AppColors.primaryLight : Colors.grey,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Statutory Quota / Reserved Seats (आरक्षण कोटा)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Allocate reserved seats (e.g. Female, Dalit, Janajati, Youth) specifically for this designation.',
                                  style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _enableQuotas,
                            activeThumbColor: AppColors.primaryLight,
                            onChanged: (val) {
                              setState(() {
                                _enableQuotas = val;
                                if (val && _quotas.isEmpty) {
                                  _quotas.add(_QuotaDraft());
                                }
                              });
                            },
                          ),
                        ],
                      ),

                      if (_enableQuotas) ...[
                        const SizedBox(height: 18),
                        const Divider(height: 1),
                        const SizedBox(height: 18),

                        // Capacity & Allocation Meter
                        _buildQuotaSummaryMeter(isDark),
                        const SizedBox(height: 20),

                        // Quota Draft Cards
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _quotas.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 14),
                          itemBuilder: (context, index) => _buildQuotaRowCard(index, isDark),
                        ),
                        const SizedBox(height: 18),

                        // Add Quota Row Button
                        OutlinedButton.icon(
                          onPressed: _addQuotaRow,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add Another Reserved Quota Category'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryLight,
                            side: const BorderSide(color: AppColors.primaryLight),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ══════════════════════════════════════════════════════════════
              // SUBMIT / CANCEL BAR
              // ══════════════════════════════════════════════════════════════
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 14),
                  LoadingButton(
                    isLoading: _isSubmitting,
                    label: _isEditing ? 'Save Changes' : 'Create Designation',
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

  // ════════════════════════════════════════════════════════════════════════════
  // 4. QUOTA CAPACITY & ALLOCATION METER
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildQuotaSummaryMeter(bool isDark) {
    final max = _maxSeats;
    final allocated = _allocatedQuotaSeats;
    final remaining = max - allocated;
    final isExceeded = remaining < 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isExceeded
            ? Colors.red.withValues(alpha: 0.1)
            : AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExceeded
              ? Colors.red.withValues(alpha: 0.4)
              : AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                isExceeded ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                color: isExceeded ? Colors.red : AppColors.primaryLight,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                'Max Capacity: $max Seat(s)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(width: 14),
              Text(
                'Quota Allocated: $allocated',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isExceeded ? Colors.red : Colors.green.shade600,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isExceeded ? Colors.red : AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isExceeded
                  ? 'Exceeded by ${-remaining} seat(s)'
                  : 'Open for General: $remaining seat(s)',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // 5. INLINE QUOTA ROW CARD
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildQuotaRowCard(int index, bool isDark) {
    final quota = _quotas[index];
    final currentText = quota.nameCtrl.text.trim().toLowerCase();

    return Material(
      color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.4) : const Color(0xFFF9FAFB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'QUOTA RULE #${index + 1}',
                        style: const TextStyle(
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_quotas.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                    tooltip: 'Remove Quota',
                    onPressed: () => _removeQuotaRow(index),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Suggested Category Chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _suggestedQuotas.map((cat) {
                final enName = cat['en']!;
                final neName = cat['ne']!;
                final isOther = enName == 'Other';
                final isStandardCat = _suggestedQuotas
                    .where((c) => c['en'] != 'Other')
                    .any((c) => c['en']!.toLowerCase() == currentText);
                final isSelected = isOther
                    ? (!isStandardCat && currentText.isNotEmpty)
                    : (currentText == enName.toLowerCase());

                return ChoiceChip(
                  label: Text(
                    '$enName ($neName)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : null,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  onSelected: (selected) {
                    if (selected) {
                      if (!isOther) {
                        setState(() => quota.nameCtrl.text = enName);
                      } else {
                        setState(() => quota.nameCtrl.clear());
                      }
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Form Inputs Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: quota.nameCtrl,
                    decoration: _dec(
                      'Quota Category Name *',
                      hint: 'e.g. Female, Dalit, Indigenous, Youth',
                      prefix: const Icon(Icons.category_rounded),
                      isDark: isDark,
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (val) => _enableQuotas && (val == null || val.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: quota.seatsCtrl,
                    decoration: _dec(
                      'Reserved Seats *',
                      hint: '1',
                      prefix: const Icon(Icons.event_seat_rounded),
                      isDark: isDark,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    validator: (val) {
                      if (!_enableQuotas) return null;
                      final n = int.tryParse(val ?? '');
                      if (n == null || n <= 0) return 'Must be >= 1';
                      if (n > _maxSeats) return 'Cannot exceed $_maxSeats';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: Material(
                    color: isDark ? AppColors.surfaceVariant : const Color(0xFFF4F4F5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            quota.status == 'active' ? 'Active' : 'Inactive',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: quota.status == 'active' ? Colors.green : Colors.grey,
                            ),
                          ),
                          Switch(
                            value: quota.status == 'active',
                            activeThumbColor: Colors.green,
                            onChanged: (val) => setState(() => quota.status = val ? 'active' : 'inactive'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: quota.descCtrl,
              decoration: _dec(
                'Statutory Description / Criteria (Optional)',
                hint: 'e.g. Reserved for female candidates of the cooperative',
                prefix: const Icon(Icons.notes_rounded),
                isDark: isDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Material(
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
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.primaryLight, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text(subtitle, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }
}
