import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';

class QuotaSettingsScreen extends ConsumerStatefulWidget {
  final String electionId;
  const QuotaSettingsScreen({super.key, required this.electionId});

  @override
  ConsumerState<QuotaSettingsScreen> createState() => _QuotaSettingsScreenState();
}

class _QuotaSettingsScreenState extends ConsumerState<QuotaSettingsScreen> {
  String? _selectedPositionFilter; // null = all positions

  String _getErrorMessage(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final messages = <String>[];
        data.forEach((key, value) {
          if (value is List) {
            messages.add(value.join(', '));
          } else if (value is String) {
            messages.add(value);
          } else {
            messages.add('$key: $value');
          }
        });
        if (messages.isNotEmpty) return messages.join('\n');
      } else if (data is String && data.isNotEmpty) {
        return data;
      }
    }
    return e.toString();
  }

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
  ];

  @override
  Widget build(BuildContext context) {
    final electionAsync = ref.watch(electionProvider(widget.electionId));
    final quotasAsync = ref.watch(quotasProvider(widget.electionId));

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Election Dashboard > Quota Settings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Main Content Card
          Expanded(
            child: Card(
              color: Theme.of(context).cardColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar with Filter & Add Button
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quota & Reserved Seats Management',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Allocate reserved seats (e.g. Female, Dalit, Open) per designation. Active quotas reflect dynamically on candidate forms & voter ballots.',
                                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        electionAsync.maybeWhen(
                          data: (election) => election.positions.isNotEmpty
                              ? ElevatedButton.icon(
                                  onPressed: () => _openAddEditDialog(context, election: election),
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add Quota'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                )
                              : const SizedBox.shrink(),
                          orElse: () => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Filter row & Summary
                    electionAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (election) {
                        return quotasAsync.maybeWhen(
                          data: (quotas) => _buildSummaryAndFilter(context, election, quotas),
                          orElse: () => const SizedBox.shrink(),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // Table Header
                    _buildTableHeader(context),
                    const Divider(),

                    // Table Body
                    Expanded(
                      child: quotasAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, _) => Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Error loading quotas: $err', style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () => ref.invalidate(quotasProvider(widget.electionId)),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                        data: (quotas) {
                          final filtered = _selectedPositionFilter == null
                              ? quotas
                              : quotas.where((q) => q.positionId == _selectedPositionFilter).toList();

                          if (filtered.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.pie_chart_outline_rounded, size: 48, color: Colors.grey[400]),
                                  const SizedBox(height: 12),
                                  Text(
                                    _selectedPositionFilter == null
                                        ? 'No quotas defined yet.'
                                        : 'No quotas defined for this designation.',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                                  ),
                                  const SizedBox(height: 8),
                                  electionAsync.maybeWhen(
                                    data: (election) => election.positions.isNotEmpty
                                        ? TextButton.icon(
                                            onPressed: () => _openAddEditDialog(context, election: election),
                                            icon: const Icon(Icons.add),
                                            label: const Text('Create your first quota'),
                                          )
                                        : const Text('Please create a designation first.'),
                                    orElse: () => const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const Divider(),
                            itemBuilder: (context, index) {
                              final quota = filtered[index];
                              return _buildTableRow(context, quota, index + 1);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryAndFilter(BuildContext context, ElectionModel election, List<PositionQuotaModel> quotas) {
    final activeCount = quotas.where((q) => q.isActive).length;
    final totalSeats = quotas.fold<int>(0, (sum, q) => sum + (q.isActive ? q.seats : 0));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Designation Filter Dropdown
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.filter_list_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Filter by Designation: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 8),
              DropdownButton<String?>(
                value: _selectedPositionFilter,
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All Designations')),
                  ...election.positions.map(
                    (p) => DropdownMenuItem<String?>(
                      value: p.id,
                      child: Text('${p.title} (${p.seatsAvailable} seats)'),
                    ),
                  ),
                ],
                onChanged: (val) => setState(() => _selectedPositionFilter = val),
              ),
            ],
          ),
          const Spacer(),
          // Stats Badges
          Row(
            children: [
              _buildStatChip('Total Quotas', '${quotas.length}', Icons.layers_outlined),
              const SizedBox(width: 12),
              _buildStatChip('Active Quotas', '$activeCount', Icons.check_circle_outline, color: Colors.green),
              const SizedBox(width: 12),
              _buildStatChip('Quota Seats', '$totalSeats', Icons.event_seat_outlined, color: AppColors.primary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, IconData icon, {Color? color}) {
    final c = color ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c)),
        ],
      ),
    );
  }

  Widget _buildTableHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(flex: 1, child: Text('S.N.', style: _headerStyle(context))),
          Expanded(flex: 3, child: Text('DESIGNATION', style: _headerStyle(context))),
          Expanded(flex: 3, child: Text('QUOTA CATEGORY', style: _headerStyle(context))),
          Expanded(flex: 2, child: Text('RESERVED SEATS', style: _headerStyle(context))),
          Expanded(flex: 2, child: Text('STATUS', style: _headerStyle(context))),
          Expanded(flex: 3, child: Text('DESCRIPTION', style: _headerStyle(context))),
          Expanded(flex: 2, child: Text('ACTION', style: _headerStyle(context))),
        ],
      ),
    );
  }

  TextStyle _headerStyle(BuildContext context) {
    return Theme.of(context).textTheme.titleSmall!.copyWith(
      color: Colors.grey[600],
      fontWeight: FontWeight.bold,
      fontSize: 12,
      letterSpacing: 1.1,
    );
  }

  Widget _buildTableRow(BuildContext context, PositionQuotaModel quota, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        children: [
          Expanded(flex: 1, child: Text('$index')),
          Expanded(
            flex: 3,
            child: Text(
              quota.positionTitle.isNotEmpty ? quota.positionTitle : 'Designation',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Text(
                  quota.name,
                  style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                const Icon(Icons.event_seat_rounded, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Text('${quota.seats} Seat(s)', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: quota.isActive ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: quota.isActive ? Colors.green.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.4)),
                ),
                child: Text(
                  quota.isActive ? 'Active' : 'Inactive',
                  style: TextStyle(
                    color: quota.isActive ? Colors.green.shade700 : Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              quota.description.isNotEmpty ? quota.description : '-',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blue),
                  tooltip: 'Edit Quota',
                  onPressed: () {
                    final election = ref.read(electionProvider(widget.electionId)).valueOrNull;
                    if (election != null) {
                      _openAddEditDialog(context, election: election, quotaToEdit: quota);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  tooltip: 'Delete Quota',
                  onPressed: () => _confirmDelete(context, quota),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openAddEditDialog(BuildContext context, {required ElectionModel election, PositionQuotaModel? quotaToEdit}) {
    final isEditing = quotaToEdit != null;
    final formKey = GlobalKey<FormState>();

    String? selectedPositionId = quotaToEdit?.positionId ?? (_selectedPositionFilter ?? (election.positions.isNotEmpty ? election.positions.first.id : null));
    final nameCtrl = TextEditingController(text: quotaToEdit?.name ?? '');
    final seatsCtrl = TextEditingController(text: quotaToEdit?.seats.toString() ?? '1');
    final descCtrl = TextEditingController(text: quotaToEdit?.description ?? '');
    String status = quotaToEdit?.status ?? 'active';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(isEditing ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(isEditing ? 'Edit Quota Setting' : 'Add Quota Setting', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Designation Selector
                        DropdownButtonFormField<String>(
                          initialValue: selectedPositionId,
                          decoration: const InputDecoration(
                            labelText: 'Designation *',
                            border: OutlineInputBorder(),
                          ),
                          items: election.positions.map((p) {
                            return DropdownMenuItem(
                              value: p.id,
                              child: Text('${p.title} (Max ${p.seatsAvailable} seats)'),
                            );
                          }).toList(),
                          onChanged: isEditing ? null : (val) => setDialogState(() => selectedPositionId = val),
                          validator: (val) => val == null ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),

                        // Quick category suggestions chips
                        const Text('Suggested Categories:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _suggestedQuotas.map((cat) {
                            final isSelected = nameCtrl.text.trim().toLowerCase() == cat.toLowerCase();
                            return ChoiceChip(
                              label: Text(cat, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : null)),
                              selected: isSelected,
                              selectedColor: AppColors.primary,
                              onSelected: (selected) {
                                if (selected) {
                                  setDialogState(() => nameCtrl.text = cat);
                                }
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),

                        // Quota Name field
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Quota Category Name *',
                            hintText: 'e.g. Female, Dalit, Youth',
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),

                        // Seats & Status Row
                        Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: TextFormField(
                                controller: seatsCtrl,
                                decoration: InputDecoration(
                                  labelText: 'Allocated Seats *',
                                  hintText: '1',
                                  helperText: () {
                                    final pos = election.positions.where((p) => p.id == selectedPositionId).firstOrNull;
                                    return pos != null ? 'Max for designation: ${pos.seatsAvailable}' : null;
                                  }(),
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                validator: (val) {
                                  final n = int.tryParse(val ?? '');
                                  if (n == null || n <= 0) return 'Must be >= 1';
                                  final pos = election.positions.where((p) => p.id == selectedPositionId).firstOrNull;
                                  if (pos != null && n > pos.seatsAvailable) {
                                    return 'Cannot exceed max ${pos.seatsAvailable} seats';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 1,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Status',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(status == 'active' ? 'Active' : 'Inactive', style: TextStyle(fontWeight: FontWeight.w600, color: status == 'active' ? Colors.green : Colors.grey)),
                                    Switch(
                                      value: status == 'active',
                                      activeThumbColor: Colors.green,
                                      onChanged: (val) => setDialogState(() => status = val ? 'active' : 'inactive'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Description
                        TextFormField(
                          controller: descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Description / Criteria (Optional)',
                            hintText: 'e.g. Reserved for female candidates of the cooperative',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final payload = {
                      'position': selectedPositionId,
                      'name': nameCtrl.text.trim(),
                      'seats': int.parse(seatsCtrl.text.trim()),
                      'status': status,
                      'description': descCtrl.text.trim(),
                    };

                    try {
                      if (isEditing) {
                        await ref.read(quotaNotifierProvider.notifier).updateQuota(widget.electionId, quotaToEdit.id, payload);
                      } else {
                        await ref.read(quotaNotifierProvider.notifier).addQuota(widget.electionId, payload);
                      }
                      if (context.mounted) {
                        Navigator.of(dialogCtx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(isEditing ? 'Quota updated successfully!' : 'Quota added successfully!')),
                        );
                      }
                    } catch (e) {
                      ref.invalidate(quotasProvider(widget.electionId));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(_getErrorMessage(e)), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: Text(isEditing ? 'Save Changes' : 'Create Quota'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, PositionQuotaModel quota) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Quota Entry?'),
        content: Text('Are you sure you want to delete quota "${quota.name}" (${quota.seats} seats) for ${quota.positionTitle}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              try {
                await ref.read(quotaNotifierProvider.notifier).deleteQuota(widget.electionId, quota.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Quota deleted successfully.')),
                  );
                }
              } catch (e) {
                ref.invalidate(quotasProvider(widget.electionId));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Delete failed: ${_getErrorMessage(e)}'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
