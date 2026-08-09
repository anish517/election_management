import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------
class _PreviewResult {
  final List<String> columns;
  final List<Map<String, dynamic>> validRows;
  final List<Map<String, dynamic>> errorRows;

  _PreviewResult({
    required this.columns,
    required this.validRows,
    required this.errorRows,
  });
}

// ---------------------------------------------------------------------------
// The Wizard Screen
// ---------------------------------------------------------------------------
class CsvImportWizardScreen extends ConsumerStatefulWidget {
  const CsvImportWizardScreen({super.key});

  @override
  ConsumerState<CsvImportWizardScreen> createState() => _CsvImportWizardScreenState();
}

class _CsvImportWizardScreenState extends ConsumerState<CsvImportWizardScreen> {
  int _step = 0; // 0=Upload, 1=Map, 2=Preview, 3=Done

  // Step 1 state
  PlatformFile? _pickedFile;

  // Step 2 state — { csvColumnHeader -> dbFieldName }
  Map<String, String> _mapping = {};
  bool _isPreviewing = false;

  // Step 3 state
  _PreviewResult? _preview;
  bool _isImporting = false;
  Map<String, dynamic>? _importResult;

  static const _dbFields = [
    'full_name',
    'email',
    'member_code',
    'phone',
    'department',
    'region',
    'position_title',
    'voting_weight',
    'photo_url',
    'gender',
    'membership_status',
    'membership_expiry_date',
    '(ignore)',
  ];

  static const _dbFieldLabels = {
    'full_name': 'Full Name',
    'email': 'Email ✱',
    'member_code': 'Member Code',
    'phone': 'Phone',
    'department': 'Department',
    'region': 'Region',
    'position_title': 'Position Title',
    'voting_weight': 'Voting Weight',
    'photo_url': 'Photo URL',
    'gender': 'Gender',
    'membership_status': 'Membership Status',
    'membership_expiry_date': 'Membership Expiry Date',
    '(ignore)': '— Ignore this column —',
  };

  // Auto-detect best mapping for a CSV column header
  String _autoMap(String col) {
    final c = col.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (c.contains('email')) return 'email';
    if (c.contains('name') || c.contains('fullname')) return 'full_name';
    if (c.contains('code') || c.contains('id') || c.contains('membercode')) return 'member_code';
    if (c.contains('phone') || c.contains('mobile') || c.contains('contact')) return 'phone';
    if (c.contains('dept') || c.contains('department')) return 'department';
    if (c.contains('region')) return 'region';
    if (c.contains('position') || c.contains('title') || c.contains('role')) return 'position_title';
    if (c.contains('weight') || c.contains('voting')) return 'voting_weight';
    if (c.contains('photo') || c.contains('image') || c.contains('avatar') || c.contains('pic')) return 'photo_url';
    if (c.contains('gender') || c.contains('sex')) return 'gender';
    if (c.contains('status')) return 'membership_status';
    if (c.contains('expire') || c.contains('expiry')) return 'membership_expiry_date';
    return '(ignore)';
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------
  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

    // Parse headers to auto-map
    final bytes = result.files.single.bytes!;
    final csvText = utf8.decode(bytes, allowMalformed: true);
    final firstLine = csvText.split('\n').first;
    final columns = firstLine.split(',').map((c) => c.trim().replaceAll('"', '')).toList();
    final autoMapping = {for (var col in columns) col: _autoMap(col)};

    setState(() {
      _pickedFile = result.files.single;
      _mapping = autoMapping;
      _step = 1;
    });
  }

  Future<void> _runPreview() async {
    if (_pickedFile == null) return;
    setState(() => _isPreviewing = true);
    try {
      final dio = ref.read(apiClientProvider);
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(_pickedFile!.bytes!, filename: _pickedFile!.name),
        'mapping': jsonEncode(_mapping),
      });
      final resp = await dio.post(ApiConstants.previewCsv, data: formData);
      setState(() {
        _preview = _PreviewResult(
          columns: List<String>.from(resp.data['columns'] ?? []),
          validRows: List<Map<String, dynamic>>.from(resp.data['valid_rows'] ?? []),
          errorRows: List<Map<String, dynamic>>.from(resp.data['error_rows'] ?? []),
        );
        _step = 2;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preview failed: $e')));
      }
    } finally {
      setState(() => _isPreviewing = false);
    }
  }

  Future<void> _runImport() async {
    if (_pickedFile == null) return;
    setState(() => _isImporting = true);
    try {
      final dio = ref.read(apiClientProvider);
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(_pickedFile!.bytes!, filename: _pickedFile!.name),
        'mapping': jsonEncode(_mapping),
      });
      final resp = await dio.post(ApiConstants.importCsv, data: formData);
      ref.invalidate(membersProvider);
      setState(() {
        _importResult = resp.data;
        _step = 3;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    } finally {
      setState(() => _isImporting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CSV Import Wizard'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () {
            if (_step == 0 || _step == 3) {
              Navigator.of(context).pop();
            } else {
              setState(() => _step = _step - 1);
            }
          },
        ),
      ),
      body: Column(
        children: [
          _buildStepIndicator(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildCurrentStep(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step Indicator
  // ---------------------------------------------------------------------------
  Widget _buildStepIndicator() {
    final steps = ['Upload', 'Map Columns', 'Preview', 'Done'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: Theme.of(context).brightness == Brightness.dark ? AppColors.surface : Colors.white,
      child: Row(
        children: steps.asMap().entries.map((entry) {
          final idx = entry.key;
          final label = entry.value;
          final isDone = idx < _step;
          final isActive = idx == _step;

          return Expanded(
            child: Row(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDone
                            ? AppColors.success
                            : isActive
                                ? AppColors.primaryLight
                                : (Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.1)),
                      ),
                      child: Center(
                        child: isDone
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  color: isActive ? Colors.white : AppColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        color: isActive ? AppColors.primaryLight : AppColors.textMuted,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                if (idx < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 18),
                      color: idx < _step ? AppColors.success : (Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.2)),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0: return _buildUploadStep();
      case 1: return _buildMapStep();
      case 2: return _buildPreviewStep();
      case 3: return _buildDoneStep();
      default: return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------------------------
  // Step 0: Upload
  // ---------------------------------------------------------------------------
  Widget _buildUploadStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Upload Your CSV File', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Upload any spreadsheet exported from Excel, Google Sheets, or any other system. The wizard will help you map the columns.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 32),

          // Drop zone
          GestureDetector(
            onTap: _pickFile,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? AppColors.surface : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primaryLight.withValues(alpha: 0.5),
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.upload_file_rounded, size: 36, color: AppColors.primaryLight),
                  ),
                  const SizedBox(height: 16),
                  const Text('Tap to browse for a CSV file', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('.csv files only', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          _buildInfoBox(
            icon: Icons.lightbulb_outline_rounded,
            color: AppColors.accent,
            title: 'Your CSV can have ANY column names',
            body: 'In the next step, you\'ll tell us which column in your file maps to which field (e.g., "Name" → Full Name, "Email Address" → Email).',
          ),

          const SizedBox(height: 16),
          _buildInfoBox(
            icon: Icons.table_chart_outlined,
            color: AppColors.primaryLight,
            title: 'Required field',
            body: 'Only the Email column is required. All other fields like name, phone, and department are optional.',
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1: Map Columns
  // ---------------------------------------------------------------------------
  Widget _buildMapStep() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Map Your Columns', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'File: ${_pickedFile?.name ?? ""}  •  ${_mapping.length} columns detected',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'For each column in your CSV, choose the matching field in our system.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 24),

                ..._mapping.entries.map((entry) => _buildColumnMappingRow(entry.key, entry.value)),
              ],
            ),
          ),
        ),
        _buildBottomBar(
          label: _isPreviewing ? 'Generating Preview...' : 'Generate Preview →',
          isLoading: _isPreviewing,
          onPressed: _runPreview,
        ),
      ],
    );
  }

  Widget _buildColumnMappingRow(String csvCol, String currentDb) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CSV Column', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                const SizedBox(height: 2),
                Text(csvCol, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, color: AppColors.textMuted, size: 18),
          const SizedBox(width: 16),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: currentDb,
              isExpanded: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.2)),
                ),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceVariant.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.05),
              ),
              items: _dbFields.map((f) => DropdownMenuItem(
                value: f,
                child: Text(
                  _dbFieldLabels[f] ?? f,
                  style: TextStyle(
                    fontSize: 12,
                    color: f == '(ignore)' ? AppColors.textMuted : null,
                    fontStyle: f == '(ignore)' ? FontStyle.italic : null,
                  ),
                ),
              )).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _mapping[csvCol] = val);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2: Preview
  // ---------------------------------------------------------------------------
  Widget _buildPreviewStep() {
    final p = _preview!;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Review Before Importing', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),

                // Summary cards
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        icon: Icons.check_circle_outline_rounded,
                        color: AppColors.success,
                        count: p.validRows.length,
                        label: 'Ready to Import',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        icon: Icons.warning_amber_rounded,
                        color: AppColors.warning,
                        count: p.errorRows.length,
                        label: 'Will Be Skipped',
                      ),
                    ),
                  ],
                ),

                if (p.errorRows.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 16),
                      const SizedBox(width: 6),
                      Text('Rows with Errors (will be skipped)',
                          style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...p.errorRows.map((e) => _buildErrorRow(e)),
                ],

                if (p.validRows.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 16),
                      const SizedBox(width: 6),
                      Text('Valid Rows (preview of first 5)',
                          style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...p.validRows.take(5).map((r) => _buildValidRowCard(r)),
                  if (p.validRows.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '+ ${p.validRows.length - 5} more valid rows...',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (p.validRows.isNotEmpty)
          _buildBottomBar(
            label: _isImporting
                ? 'Importing...'
                : 'Import ${p.validRows.length} Member${p.validRows.length == 1 ? '' : 's'}',
            isLoading: _isImporting,
            onPressed: _runImport,
            color: AppColors.success,
          )
        else
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back & Fix Mapping'),
                onPressed: () => setState(() => _step = 1),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSummaryCard({required IconData icon, required Color color, required int count, required String label}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text('$count', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _buildErrorRow(Map<String, dynamic> errorRow) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('Row ${errorRow['row']}',
                style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(errorRow['error'] ?? 'Unknown error',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildValidRowCard(Map<String, dynamic> r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.surface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline_rounded, color: AppColors.textMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r['full_name']?.toString().isNotEmpty == true ? r['full_name'] : '(No name)',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(r['email'] ?? '', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          if (r['member_code']?.toString().isNotEmpty == true)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(r['member_code'], style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 3: Done
  // ---------------------------------------------------------------------------
  Widget _buildDoneStep() {
    final r = _importResult;
    final imported = r?['imported'] ?? 0;
    final skipped = r?['skipped'] ?? 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, size: 64, color: AppColors.success),
            ),
            const SizedBox(height: 24),
            Text('Import Complete!', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text('$imported member${imported == 1 ? '' : 's'} added successfully.',
                style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
            if (skipped > 0) ...[
              const SizedBox(height: 6),
              Text('$skipped row${skipped == 1 ? '' : 's'} were skipped (duplicates or errors).',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.group_rounded),
                label: const Text('View Member List'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() {
                _step = 0;
                _pickedFile = null;
                _mapping = {};
                _preview = null;
                _importResult = null;
              }),
              child: const Text('Import Another File'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  Widget _buildBottomBar({
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.surface : Colors.white,
        border: Border(top: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.1))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? AppColors.primaryLight,
          ),
          child: isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ),
    );
  }

  Widget _buildInfoBox({required IconData icon, required Color color, required String title, required String body}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
