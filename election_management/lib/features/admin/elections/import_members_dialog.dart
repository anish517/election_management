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

class _ImportMembersDialogState extends ConsumerState<ImportMembersDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Tab 1: Org Roster state
  bool _importAll = true;
  final Set<String> _selectedMemberIds = {};
  String _searchQuery = '';
  bool _isOrgSubmitting = false;

  // Tab 2: External API state
  final _apiUrlController = TextEditingController();
  String _authType = 'none'; // 'none', 'bearer', 'custom'
  final _tokenController = TextEditingController();
  final _customHeaderNameController = TextEditingController(text: 'X-API-KEY');
  final _customHeaderValueController = TextEditingController();

  bool _isFetchingApi = false;
  bool _isImportingApi = false;
  List<Map<String, dynamic>> _apiPreviewRecords = [];
  int _apiTotalFound = 0;
  String? _apiErrorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _apiUrlController.dispose();
    _tokenController.dispose();
    _customHeaderNameController.dispose();
    _customHeaderValueController.dispose();
    super.dispose();
  }

  Future<void> _submitOrgMembers(List<MemberModel> members) async {
    setState(() => _isOrgSubmitting = true);
    try {
      final dio = ref.read(apiClientProvider);
      final url = ApiConstants.importElectionMembers(widget.electionId);

      final payload = <String, dynamic>{};
      if (!_importAll) {
        if (_selectedMemberIds.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select at least one member to import.')),
          );
          setState(() => _isOrgSubmitting = false);
          return;
        }
        payload['member_ids'] = _selectedMemberIds.toList();
      }

      final response = await dio.post(url, data: payload);
      final message = response.data['message'] ?? 'Members imported successfully!';

      ref.invalidate(votersProvider(widget.electionId));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.green));
      }
    } on DioException catch (e) {
      if (mounted) {
        final err = e.response?.data is Map ? e.response?.data['error'] ?? e.message : e.message;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $err'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isOrgSubmitting = false);
    }
  }

  Map<String, dynamic> _buildApiPayload({required bool previewOnly}) {
    final payload = <String, dynamic>{
      'url': _apiUrlController.text.trim(),
      'preview_only': previewOnly,
    };

    if (_authType == 'bearer') {
      final token = _tokenController.text.trim();
      if (token.isNotEmpty) {
        payload['auth_header'] = token.startsWith('Bearer ') ? token : 'Bearer $token';
      }
    } else if (_authType == 'custom') {
      final hName = _customHeaderNameController.text.trim();
      final hVal = _customHeaderValueController.text.trim();
      if (hName.isNotEmpty && hVal.isNotEmpty) {
        payload['custom_header_name'] = hName;
        payload['custom_header_value'] = hVal;
      }
    }

    return payload;
  }

  Future<void> _fetchExternalApiPreview() async {
    final url = _apiUrlController.text.trim();
    if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      setState(() => _apiErrorMessage = 'Please enter a valid HTTP/HTTPS endpoint URL.');
      return;
    }

    setState(() {
      _isFetchingApi = true;
      _apiErrorMessage = null;
      _apiPreviewRecords = [];
      _apiTotalFound = 0;
    });

    try {
      final dio = ref.read(apiClientProvider);
      final postUrl = ApiConstants.importExternalApiVoters(widget.electionId);
      final response = await dio.post(postUrl, data: _buildApiPayload(previewOnly: true));

      final data = response.data;
      if (data is Map) {
        final preview = (data['preview'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        setState(() {
          _apiPreviewRecords = preview;
          _apiTotalFound = data['total_found'] as int? ?? preview.length;
        });
      }
    } on DioException catch (e) {
      final err = e.response?.data is Map
          ? (e.response?.data['error'] is Map ? e.response?.data['error']['message'] : e.response?.data['error']) ?? e.message
          : e.message;
      setState(() => _apiErrorMessage = err?.toString() ?? 'Failed to connect to external API.');
    } catch (e) {
      setState(() => _apiErrorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isFetchingApi = false);
    }
  }

  Future<void> _importExternalApiVoters() async {
    setState(() => _isImportingApi = true);
    try {
      final dio = ref.read(apiClientProvider);
      final postUrl = ApiConstants.importExternalApiVoters(widget.electionId);
      final response = await dio.post(postUrl, data: _buildApiPayload(previewOnly: false));

      final data = response.data;
      final message = data is Map ? data['message'] ?? 'External voters imported successfully!' : 'Imported successfully!';

      ref.invalidate(votersProvider(widget.electionId));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message.toString()),
          backgroundColor: Colors.green,
        ));
      }
    } on DioException catch (e) {
      final err = e.response?.data is Map
          ? (e.response?.data['error'] is Map ? e.response?.data['error']['message'] : e.response?.data['error']) ?? e.message
          : e.message;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Import failed: $err'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Import error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isImportingApi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 850,
        height: 680,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.sync_alt_rounded, color: AppColors.primary, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Import Voters via API',
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
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: AppColors.primary,
                unselectedLabelColor: Colors.grey.shade600,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
                  ],
                ),
                tabs: const [
                  Tab(icon: Icon(Icons.groups_outlined, size: 18), text: 'Organization Roster'),
                  Tab(icon: Icon(Icons.cloud_download_outlined, size: 18), text: 'External API Endpoint'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOrgRosterTab(),
                  _buildExternalApiTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrgRosterTab() {
    final membersAsync = ref.watch(membersProvider);

    return membersAsync.when(
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
            Text(
              'Sync and import registered organization members directly into this election\'s voter roll without CSV upload.',
              style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color),
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    groupValue: _importAll,
                    onChanged: (val) => setState(() => _importAll = val ?? true),
                    title: Text('Import All Eligible Active Members (${eligibleMembers.length})',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
                Expanded(
                  child: RadioListTile<bool>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    groupValue: _importAll,
                    onChanged: (val) => setState(() => _importAll = val ?? false),
                    title: const Text('Select Specific Members',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
              ],
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
                    separatorBuilder: (_, _) => const Divider(height: 1),
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
                  onPressed: _isOrgSubmitting ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isOrgSubmitting ? null : () => _submitOrgMembers(members),
                  icon: _isOrgSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync_rounded, size: 18),
                  label: Text(_isOrgSubmitting
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
    );
  }

  Widget _buildExternalApiTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect to an external MIS / CRM / Organization API to fetch and import voter records live.',
            style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color),
          ),
          const SizedBox(height: 14),

          // API URL Field
          TextFormField(
            controller: _apiUrlController,
            decoration: const InputDecoration(
              labelText: 'External API Endpoint URL *',
              hintText: 'https://partner-portal.org/api/v1/members',
              prefixIcon: Icon(Icons.link_rounded),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),

          // Authentication Config
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _authType,
                  decoration: const InputDecoration(
                    labelText: 'Authentication Type',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('No Authentication (Public)')),
                    DropdownMenuItem(value: 'bearer', child: Text('Bearer Token')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom API Key / Header')),
                  ],
                  onChanged: (val) => setState(() => _authType = val ?? 'none'),
                ),
              ),
              const SizedBox(width: 12),
              if (_authType == 'bearer')
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _tokenController,
                    decoration: const InputDecoration(
                      labelText: 'Bearer Token *',
                      hintText: 'eyJhbGciOi...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                )
              else if (_authType == 'custom') ...[
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _customHeaderNameController,
                    decoration: const InputDecoration(
                      labelText: 'Header Name',
                      hintText: 'X-API-KEY',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _customHeaderValueController,
                    decoration: const InputDecoration(
                      labelText: 'Header Value',
                      hintText: 'SecretKey...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Test & Fetch Button
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isFetchingApi ? null : _fetchExternalApiPreview,
                icon: _isFetchingApi
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download_rounded, size: 18),
                label: Text(_isFetchingApi ? 'Testing & Fetching...' : 'Test & Fetch Voters'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF563D7C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Fetches live JSON from external server securely with automated field mapping.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ],
          ),

          if (_apiErrorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_apiErrorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],

          if (_apiPreviewRecords.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Found $_apiTotalFound voter records from external API. Previewing first ${_apiPreviewRecords.length}:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.green.shade800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.separated(
                itemCount: _apiPreviewRecords.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, idx) {
                  final r = _apiPreviewRecords[idx];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: Text('${idx + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    ),
                    title: Text('${r['first_name']} ${r['last_name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text('ID: ${r['voter_id']} • Email: ${r['email']} • Phone: ${r['phone']}', style: const TextStyle(fontSize: 11)),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isImportingApi ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isImportingApi ? null : _importExternalApiVoters,
                  icon: _isImportingApi
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: Text(_isImportingApi ? 'Importing...' : 'Import All ($_apiTotalFound Voters)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
