import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';
import 'create_designation_screen.dart';
import 'quota_settings_screen.dart';

class DesignationsScreen extends ConsumerWidget {
  final String electionId;
  const DesignationsScreen({super.key, required this.electionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final electionAsync = ref.watch(electionProvider(electionId));

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Election Dashboard > Designations',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 24),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: const Text('Quota & Reserved Seats')),
                                  body: QuotaSettingsScreen(electionId: electionId),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.pie_chart_outline_rounded, size: 18),
                          label: const Text('Manage Quotas'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CreateDesignationScreen(electionId: electionId),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add New Record'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Table Header
                    _buildTableHeader(context),
                    const Divider(),
                    // Table Body
                    Expanded(
                      child: electionAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, _) => Center(child: Text('Error: $err')),
                        data: (election) {
                          if (election.positions.isEmpty) {
                            return const Center(child: Text('No designations found.'));
                          }
                          return ListView.separated(
                            itemCount: election.positions.length,
                            separatorBuilder: (context, index) => const Divider(),
                            itemBuilder: (context, index) {
                              final pos = election.positions[index];
                              return _buildTableRow(context, ref, pos, index + 1);
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

  Widget _buildTableHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(flex: 1, child: Text('S.N.', style: _headerStyle(context))),
          Expanded(flex: 3, child: Text('DESIGNATION', style: _headerStyle(context))),
          Expanded(flex: 1, child: Text('SEATS', style: _headerStyle(context))),
          Expanded(flex: 2, child: Text('QUOTA', style: _headerStyle(context))),
          Expanded(flex: 2, child: Text('NOMINEE CHARGE', style: _headerStyle(context))),
          Expanded(flex: 2, child: Text('RESULT ORDER', style: _headerStyle(context))),
          Expanded(flex: 2, child: Text('BACKGROUND', style: _headerStyle(context))),
          Expanded(flex: 1, child: Text('ACTION', style: _headerStyle(context))),
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

  Widget _buildTableRow(BuildContext context, WidgetRef ref, PositionModel pos, int index) {
    Color parseColor(String hex) {
      try {
        final h = hex.replaceAll('#', '');
        return Color(int.parse('FF$h', radix: 16));
      } catch (_) {
        return Colors.grey;
      }
    }

    final bgColor = parseColor(pos.bgColor);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Expanded(flex: 1, child: Text(index.toString())),
          Expanded(flex: 3, child: Text(pos.title)),
          Expanded(flex: 1, child: Text(pos.seatsAvailable.toString())),
          Expanded(
            flex: 2,
            child: pos.quotas.isNotEmpty
                ? Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: pos.quotas.map((q) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: q.isActive ? AppColors.primary.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: q.isActive ? AppColors.primary.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        '${q.name}: ${q.seats}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: q.isActive ? AppColors.primaryLight : Colors.grey[600],
                        ),
                      ),
                    )).toList(),
                  )
                : Text(pos.quotaName.isEmpty ? '-' : pos.quotaName, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(flex: 2, child: Text('Rs. ${pos.nomineeCharge}')),
          Expanded(flex: 2, child: Text(pos.resultOrder.toString())),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  pos.bgColor,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  tooltip: 'Delete Designation',
                  onPressed: () => _confirmDelete(context, ref, pos),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, PositionModel pos) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red),
            const SizedBox(width: 8),
            const Text('Delete Designation?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${pos.title}"?\n\nThis will also remove any quota configurations associated with this designation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              try {
                await ref
                    .read(publishElectionProvider.notifier)
                    .deletePosition(electionId, pos.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Designation "${pos.title}" deleted successfully.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  final errorMsg = _extractErrorMessage(e);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMsg),
                      backgroundColor: Colors.red.shade700,
                      duration: const Duration(seconds: 4),
                    ),
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

  String _extractErrorMessage(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        if (data['error'] is Map && data['error']['message'] != null) {
          return data['error']['message'].toString();
        }
        if (data['detail'] != null) return data['detail'].toString();
        if (data['message'] != null) return data['message'].toString();
      }
    }
    return 'Failed to delete designation: $e';
  }
}
