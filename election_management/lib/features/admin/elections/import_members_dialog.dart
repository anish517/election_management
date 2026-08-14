import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/models.dart';

class ImportMembersDialog extends ConsumerStatefulWidget {
  final String electionId;
  const ImportMembersDialog({super.key, required this.electionId});

  @override
  ConsumerState<ImportMembersDialog> createState() => _ImportMembersDialogState();
}

class _ImportMembersDialogState extends ConsumerState<ImportMembersDialog> {
  bool _importAll = true;
  final Set<String> _selectedMemberIds = {};
  String _searchQuery = '';
  bool _isSubmitting = false;

  Future<void> _submit(List<MemberModel> members) async {
    setState(() => _isSubmitting = true);
    try {
      final dio = ref.read(apiClientProvider);
      final url = ApiConstants.importElectionMembers(widget.electionId);

      final payload = <String, dynamic>{};
      if (!_importAll) {
        if (_selectedMemberIds.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select at least one member to import.')),
          );
          setState(() => _isSubmitting = false);
          return;
        }
        payload['member_ids'] = _selectedMemberIds.toList();
      }

      final response = await dio.post(url, data: payload);
      final message = response.data['message'] ?? 'Members imported successfully!';

      ref.invalidate(votersProvider(widget.electionId));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } on DioException catch (e) {
      if (mounted) {
        final err = e.response?.data is Map ? e.response?.data['error'] ?? e.message : e.message;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $err')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 700,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: membersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Failed to load organization members: $e')),
          data: (members) {
            final eligibleMembers = members.where((m) => m.isEligibleToVote).toList();
            final filteredMembers = members.where((m) {
              final query = _searchQuery.toLowerCase();
              return m.fullName.toLowerCase().contains(query) ||
                  m.email.toLowerCase().contains(query) ||
                  m.memberCode.toLowerCase().contains(query);
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.people_alt_rounded, color: AppColors.primary, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'Import from Organization Members API',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Sync and import registered organization members directly into this election\'s voter roll without CSV upload.',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color),
                ),
                const Divider(height: 24),
                // Radio Option 1: Import All
                RadioListTile<bool>(
                  value: true,
                  groupValue: _importAll,
                  onChanged: (val) => setState(() => _importAll = val ?? true),
                  title: Text('Import All Eligible Active Members (${eligibleMembers.length})'),
                  subtitle: const Text('Automatically pulls all active members marked as eligible to vote in organization settings.'),
                ),
                // Radio Option 2: Select Specific
                RadioListTile<bool>(
                  value: false,
                  groupValue: _importAll,
                  onChanged: (val) => setState(() => _importAll = val ?? false),
                  title: const Text('Select Specific Members'),
                  subtitle: const Text('Choose individual members from the list below.'),
                ),
                if (!_importAll) ...[
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search by name, email, or member code...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Selected: ${_selectedMemberIds.length} of ${members.length}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => setState(() {
                              _selectedMemberIds.addAll(filteredMembers.map((m) => m.id));
                            }),
                            child: const Text('Select All Filtered', style: TextStyle(fontSize: 12)),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _selectedMemberIds.clear()),
                            child: const Text('Clear', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        itemCount: filteredMembers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, idx) {
                          final m = filteredMembers[idx];
                          final isSelected = _selectedMemberIds.contains(m.id);
                          return CheckboxListTile(
                            dense: true,
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedMemberIds.add(m.id);
                                } else {
                                  _selectedMemberIds.remove(m.id);
                                }
                              });
                            },
                            title: Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: Text('${m.email} • Code: ${m.memberCode.isNotEmpty ? m.memberCode : "N/A"}', style: const TextStyle(fontSize: 11)),
                            secondary: m.isEligibleToVote
                                ? const Icon(Icons.check_circle_outline, color: AppColors.success, size: 18)
                                : const Icon(Icons.cancel_outlined, color: Colors.grey, size: 18),
                          );
                        },
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : () => _submit(members),
                      icon: _isSubmitting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.sync_rounded, size: 18),
                      label: Text(_isSubmitting
                          ? 'Importing...'
                          : _importAll
                              ? 'Import All (${eligibleMembers.length})'
                              : 'Import Selected (${_selectedMemberIds.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
