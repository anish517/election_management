import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';

class _QuotaDraft {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController seatsCtrl = TextEditingController(text: '1');
  final TextEditingController descCtrl = TextEditingController();
  String status = 'active';

  void dispose() {
    nameCtrl.dispose();
    seatsCtrl.dispose();
    descCtrl.dispose();
  }
}

class CreateDesignationScreen extends ConsumerStatefulWidget {
  final String electionId;
  const CreateDesignationScreen({super.key, required this.electionId});

  @override
  ConsumerState<CreateDesignationScreen> createState() =>
      _CreateDesignationScreenState();
}

class _CreateDesignationScreenState
    extends ConsumerState<CreateDesignationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _seatsController = TextEditingController(text: '1');
  final _chargeController = TextEditingController(text: '0.00');
  final _orderController = TextEditingController(text: '0');
  Color _selectedColor = const Color(0xFF563D7C);

  bool _enableQuotas = false;
  final List<_QuotaDraft> _quotas = [];

  bool _isSubmitting = false;

  static const List<String> _suggestedQuotas = [
    'Female',
    'Dalit',
    'Janajati',
    'Youth',
    'Madhesi',
    'Muslim',
    'Khas Arya',
    'Tharu',
    'Open / General',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
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
      builder: (context) {
        return AlertDialog(
          title: const Text('Pick Background Color'),
          content: SingleChildScrollView(
            child: BlockPicker(
              pickerColor: _selectedColor,
              onColorChanged: (color) {
                setState(() => _selectedColor = color);
                Navigator.of(context).pop();
              },
            ),
          ),
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
    if (!_formKey.currentState!.validate()) return;

    if (_enableQuotas) {
      if (_quotas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please add at least one quota row or disable Quota toggle.'),
            backgroundColor: Colors.orange,
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
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final hexColor =
          '#${_selectedColor.toARGB32().toRadixString(16).substring(2, 8)}';

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

      final createdPosition = await ref
          .read(publishElectionProvider.notifier)
          .addPosition(data);

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
          const SnackBar(
            content: Text('Designation & Quotas created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Designation'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Election Dashboard > Designations > Create Designation',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Designation Information',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildTextField(
                              'Designation Name *',
                              _titleController,
                              hintText: 'e.g. President, General Secretary, Board Member',
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 1,
                            child: _buildTextField(
                              'Max Seats *',
                              _seatsController,
                              helperText: 'Total winners for this designation',
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
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildTextField(
                              'Nominee Charge (NPR)',
                              _chargeController,
                              helperText: 'Candidacy fee if applicable',
                              keyboardType: TextInputType.number,
                              required: false,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: _buildTextField(
                              'Result Order',
                              _orderController,
                              helperText:
                                  'Lower numbers appear first on ballot & results',
                              keyboardType: TextInputType.number,
                              required: false,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Background Color',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: _pickColor,
                                  child: Container(
                                    height: 48,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: Container(
                                            margin: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: _selectedColor,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Center(
                                            child: Text(
                                              '#${_selectedColor.toARGB32().toRadixString(16).substring(2, 8).toUpperCase()}',
                                              style: TextStyle(
                                                color: Colors.grey.shade700,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),

                      // =======================================================
                      // Quota Toggle & Embedded Settings Section
                      // =======================================================
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _enableQuotas
                              ? AppColors.primary.withValues(alpha: 0.04)
                              : Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _enableQuotas
                                ? AppColors.primary.withValues(alpha: 0.3)
                                : Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: _enableQuotas
                                            ? AppColors.primary.withValues(alpha: 0.1)
                                            : Colors.grey.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.pie_chart_rounded,
                                        color: _enableQuotas ? AppColors.primary : Colors.grey,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Quota / Reserved Seats for this Designation',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Allocate reserved seats (e.g. Female, Dalit, Open) for this designation.',
                                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                // Yes/No Toggle Button
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildToggleButton(
                                        label: 'No',
                                        isSelected: !_enableQuotas,
                                        onTap: () {
                                          setState(() => _enableQuotas = false);
                                        },
                                      ),
                                      _buildToggleButton(
                                        label: 'Yes',
                                        isSelected: _enableQuotas,
                                        onTap: () {
                                          setState(() {
                                            _enableQuotas = true;
                                            if (_quotas.isEmpty) {
                                              _quotas.add(_QuotaDraft());
                                            }
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            if (_enableQuotas) ...[
                              const Divider(height: 32),
                              // Allocation Summary Bar
                              _buildQuotaSummaryBar(),
                              const SizedBox(height: 20),

                              // Quota Rows
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _quotas.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 16),
                                itemBuilder: (context, index) {
                                  return _buildQuotaRowCard(index);
                                },
                              ),

                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _addQuotaRow,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Add Another Quota Category'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side: const BorderSide(color: AppColors.primary),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 48),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.grey.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Create Designation', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildQuotaSummaryBar() {
    final max = _maxSeats;
    final allocated = _allocatedQuotaSeats;
    final remaining = max - allocated;
    final isExceeded = remaining < 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isExceeded ? Colors.red.shade50 : AppColors.primaryLight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isExceeded ? Colors.red.shade300 : AppColors.primaryLight.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                isExceeded ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                color: isExceeded ? Colors.red : AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                'Total Seats: $max',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(width: 16),
              Text(
                'Quota Allocated: $allocated',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isExceeded ? Colors.red : Colors.green.shade700,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isExceeded ? Colors.red : AppColors.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isExceeded
                  ? 'Exceeded by ${-remaining} seat(s)'
                  : 'Remaining Open: $remaining seat(s)',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaRowCard(int index) {
    final quota = _quotas[index];
    final currentText = quota.nameCtrl.text.trim().toLowerCase();
    final isStandardCat = _suggestedQuotas
        .where((c) => c != 'Other')
        .any((c) => c.toLowerCase() == currentText);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Quota Category #${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              if (_quotas.length > 1)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  tooltip: 'Remove Quota',
                  onPressed: () => _removeQuotaRow(index),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Suggestion Chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _suggestedQuotas.map((cat) {
              final isOtherChip = cat == 'Other';
              final isSelected = isOtherChip
                  ? (!isStandardCat)
                  : (currentText == cat.toLowerCase());
              return ChoiceChip(
                avatar: isOtherChip ? Icon(Icons.edit_note_rounded, size: 14, color: isSelected ? Colors.white : AppColors.primary) : null,
                label: Text(
                  isOtherChip ? 'Other (Manual Entry)' : cat,
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
                    if (!isOtherChip) {
                      setState(() => quota.nameCtrl.text = cat);
                    } else {
                      setState(() {
                        quota.nameCtrl.clear();
                      });
                    }
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: quota.nameCtrl,
                  decoration: InputDecoration(
                    labelText: isStandardCat
                        ? 'Quota Category Name *'
                        : 'Custom Quota Name * (Manual Entry)',
                    hintText: isStandardCat
                        ? 'e.g. Female, Dalit, Open'
                        : 'Type any custom quota name (e.g. Indigenous, Minority)',
                    helperText: isStandardCat
                        ? 'Preset selected. Tap "Other (Manual Entry)" to type custom name.'
                        : 'Type your custom self-defined quota label.',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (val) => _enableQuotas && (val == null || val.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: quota.seatsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Reserved Seats *',
                    hintText: '1',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (val) {
                    if (!_enableQuotas) return null;
                    final n = int.tryParse(val ?? '');
                    if (n == null || n <= 0) return 'Must be >= 1';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        quota.status == 'active' ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
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
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: quota.descCtrl,
            decoration: const InputDecoration(
              labelText: 'Description / Criteria (Optional)',
              hintText: 'e.g. Reserved for female candidates of the organization',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    String? hintText,
    String? helperText,
    bool required = true,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
    FormFieldValidator<String>? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hintText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          validator: validator ??
              ((val) => (required && (val == null || val.trim().isEmpty))
                  ? 'Required'
                  : null),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            helperText,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
