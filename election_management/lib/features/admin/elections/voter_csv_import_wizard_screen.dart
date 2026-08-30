import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/utils/download_helper.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loading_button.dart';

class _PreviewResult {
  final List<String> columns;
  final List<Map<String, dynamic>> validRows;
  final List<Map<String, dynamic>> errorRows;
  _PreviewResult({required this.columns, required this.validRows, required this.errorRows});
}

class VoterCsvImportWizardScreen extends ConsumerStatefulWidget {
  final String electionId;
  const VoterCsvImportWizardScreen({super.key, required this.electionId});

  @override
  ConsumerState<VoterCsvImportWizardScreen> createState() => _VoterCsvImportWizardScreenState();
}

class _VoterCsvImportWizardScreenState extends ConsumerState<VoterCsvImportWizardScreen> {
  int _step = 0;
  PlatformFile? _pickedFile;
  Map<String, String> _mapping = {};
  bool _isPreviewing = false;
  _PreviewResult? _preview;
  bool _isImporting = false;
  Map<String, dynamic>? _importResult;

  static const _dbFields = [
    'voter_id',
    'prefix',
    'first_name',
    'middle_name',
    'last_name',
    'email',
    'phone',
    'council_number',
    'citizenship_number',
    '(ignore)'
  ];

  static const _dbFieldLabels = {
    'voter_id': 'Voter ID (मतदाता नं)',
    'prefix': 'Prefix (Mr/Ms/Dr)',
    'first_name': 'First Name * (पहिलो नाम)',
    'middle_name': 'Middle Name (बीचको नाम)',
    'last_name': 'Last Name * (थर)',
    'email': 'Email (इमेल ठेगाना)',
    'phone': 'Phone (सम्पर्क नं)',
    'council_number': 'Council Number (दर्ता नं)',
    'citizenship_number': 'Citizenship Number (नागरिकता नं)',
    '(ignore)': '— Ignore this column (उपेक्षा गर्नुहोस्) —',
  };

  String _autoMap(String col) {
    final c = col.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (c.contains('email')) return 'email';
    if (c.contains('first')) return 'first_name';
    if (c.contains('last') || c.contains('sur')) return 'last_name';
    if (c.contains('middle')) return 'middle_name';
    if (c == 'name' || c == 'fullname') return 'first_name';
    if (c.contains('voter') || c == 'id' || c.endsWith('id') || c.contains('code') || c.contains('roll')) return 'voter_id';
    if (c.contains('phone') || c.contains('mobile') || c.contains('contact')) return 'phone';
    if (c.contains('council') || c.contains('license') || c.contains('reg')) return 'council_number';
    if (c.contains('citizen') || c.contains('nagrikta')) return 'citizenship_number';
    if (c.contains('prefix') || c.contains('salutation') || c.contains('title')) return 'prefix';
    return '(ignore)';
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;

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
      final resp = await dio.post(ApiConstants.previewElectionVotersCsv(widget.electionId), data: formData);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Preview validation failed: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPreviewing = false);
    }
  }

  Future<void> _runImport() async {
    if (_pickedFile == null) return;
    setState(() => _isImporting = true);
    try {
      final dio = ref.read(apiClientProvider);

      if (_preview != null) {
        final editedCsv = _generateEditedCsv();
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(utf8.encode(editedCsv), filename: 'edited.csv'),
          'mapping': jsonEncode({}),
        });
        final resp = await dio.post(ApiConstants.importElectionVotersCsv(widget.electionId), data: formData);
        ref.invalidate(votersProvider(widget.electionId));
        setState(() {
          _importResult = resp.data;
          _step = 3;
        });
      } else {
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(_pickedFile!.bytes!, filename: _pickedFile!.name),
          'mapping': jsonEncode(_mapping),
        });
        final resp = await dio.post(ApiConstants.importElectionVotersCsv(widget.electionId), data: formData);
        ref.invalidate(votersProvider(widget.electionId));
        setState(() {
          _importResult = resp.data;
          _step = 3;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  String _generateEditedCsv() {
    final allRows = [..._preview!.validRows, ..._preview!.errorRows];
    if (allRows.isEmpty) return "";

    final headers = _dbFields.where((f) => f != '(ignore)').toList();
    final sb = StringBuffer();
    sb.writeln(headers.join(','));

    for (var row in allRows) {
      final data = row.containsKey('data') ? row['mapped'] as Map<String, dynamic> : row;
      final values = headers.map((h) => '"${(data[h] ?? '').toString().replaceAll('"', '""')}"');
      sb.writeln(values.join(','));
    }
    return sb.toString();
  }

  void _downloadTemplate() {
    const header = "voter_id,prefix,first_name,middle_name,last_name,email,phone,council_number,citizenship_number\n"
        "V-001,Mr.,Ramesh,Prasad,Shrestha,ramesh@example.com,9841000001,NNC-101,27-01-76-00001\n"
        "V-002,Ms.,Sita,,Sharma,sita@example.com,9841000002,,27-01-76-00002\n";
    final bytes = utf8.encode(header);
    final base64String = base64Encode(bytes);

    try {
      downloadFileFromBase64(base64String, 'voters_import_template.csv');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.download_done_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text('Sample CSV template downloaded successfully!'),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not download template: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bulk CSV Voter Roll Importer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('मतदाता सूची CSV आयात विगार्ड', style: TextStyle(fontSize: 11, color: Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.65) ?? Colors.white70)),
          ],
        ),
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              // Custom Progress Tracker
              _buildStepTracker(isDark),
              const Divider(height: 1),

              // Active Step View
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildCurrentStep(isDark),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepTracker(bool isDark) {
    final stepTitles = ['1. Upload File', '2. Map Schema', '3. Review & Fix', '4. Complete'];
    final stepIcons = [Icons.cloud_upload_outlined, Icons.sync_alt_rounded, Icons.fact_check_outlined, Icons.check_circle_outline_rounded];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
      child: Row(
        children: List.generate(stepTitles.length, (index) {
          final isCompleted = _step > index;
          final isCurrent = _step == index;
          final color = isCurrent ? AppColors.primaryLight : (isCompleted ? Colors.green : (isDark ? Colors.white38 : Colors.grey.shade400));

          return Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : (isCompleted ? Colors.green.withValues(alpha: 0.12) : Colors.transparent),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: isCurrent ? 2 : 1),
                  ),
                  child: Icon(
                    isCompleted ? Icons.check_rounded : stepIcons[index],
                    color: color,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stepTitles[index],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                      color: isCurrent ? (isDark ? Colors.white : Colors.black87) : color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (index < stepTitles.length - 1)
                  Container(
                    width: 20,
                    height: 1.5,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: isCompleted ? Colors.green : (isDark ? Colors.white12 : Colors.grey.shade300),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep(bool isDark) {
    switch (_step) {
      case 0:
        return _buildStepUpload(isDark);
      case 1:
        return _buildStepMap(isDark);
      case 2:
        return _buildStepPreview(isDark);
      case 3:
      default:
        return _buildStepDone(isDark);
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // STEP 1: UPLOAD
  // ══════════════════════════════════════════════════════════════════
  Widget _buildStepUpload(bool isDark) {
    return ListView(
      children: [
        // Dropzone Hero Box
        InkWell(
          onTap: _pickFile,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.4) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.4),
                width: 2,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_upload_rounded, size: 48, color: AppColors.primaryLight),
                ),
                const SizedBox(height: 18),
                Text(
                  'Select or Browse Voter CSV File',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Upload your organization voter roster (.csv format, UTF-8 encoded)',
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Download Sample Template'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _downloadTemplate,
                    ),
                    const SizedBox(width: 14),
                    FilledButton.icon(
                      icon: const Icon(Icons.file_open_rounded, size: 18),
                      label: const Text('Browse Computer'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _pickFile,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Schema & Template Specs Card
        Material(
          color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.2) : const Color(0xFFFAFAFA),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.primaryLight, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Recommended CSV Headers & Format Specifications',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    Chip(label: Text('voter_id (Unique ID)'), avatar: Icon(Icons.check, size: 14)),
                    Chip(label: Text('first_name * (Required)'), avatar: Icon(Icons.star, size: 14, color: Colors.orange)),
                    Chip(label: Text('last_name * (Required)'), avatar: Icon(Icons.star, size: 14, color: Colors.orange)),
                    Chip(label: Text('email (Credentials Dispatch)'), avatar: Icon(Icons.check, size: 14)),
                    Chip(label: Text('phone (SMS Verification)'), avatar: Icon(Icons.check, size: 14)),
                    Chip(label: Text('citizenship_number (Identity)'), avatar: Icon(Icons.check, size: 14)),
                    Chip(label: Text('council_number (License)'), avatar: Icon(Icons.check, size: 14)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // STEP 2: SCHEMA MAPPING
  // ══════════════════════════════════════════════════════════════════
  Widget _buildStepMap(bool isDark) {
    if (_pickedFile == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // File banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.description_outlined, color: AppColors.primaryLight),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Selected File: ${_pickedFile!.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('${_mapping.keys.length} columns detected in CSV header row.', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Change File', style: TextStyle(fontSize: 12)),
                onPressed: _pickFile,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Mapping table container
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.3) : Colors.white,
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListView.separated(
              itemCount: _mapping.keys.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final csvCol = _mapping.keys.elementAt(i);
                final currentMap = _mapping[csvCol];
                final isAutoMapped = currentMap != null && currentMap != '(ignore)';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Text(csvCol, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            if (isAutoMapped) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('Auto-matched', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_right_alt_rounded, color: AppColors.primaryLight, size: 24),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          initialValue: currentMap,
                          isExpanded: true,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            filled: true,
                            fillColor: isDark ? AppColors.surfaceVariant : const Color(0xFFF9FAFB),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: _dbFields.map((f) => DropdownMenuItem(value: f, child: Text(_dbFieldLabels[f]!, style: const TextStyle(fontSize: 13)))).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _mapping[csvCol] = val);
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Action toolbar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _step = 0),
              child: const Text('Back to Upload'),
            ),
            LoadingButton(
              label: 'Proceed to Validation Preview',
              icon: Icons.fact_check_outlined,
              isLoading: _isPreviewing,
              onPressed: _runPreview,
              fullWidth: false,
            ),
          ],
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // STEP 3: PREVIEW & INTERACTIVE REPAIR
  // ══════════════════════════════════════════════════════════════════
  Widget _buildStepPreview(bool isDark) {
    if (_preview == null) return const SizedBox.shrink();
    final valid = _preview!.validRows;
    final errors = _preview!.errorRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Validation Metric Cards
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${valid.length}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                        const Text('Valid Qualified Rows', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${errors.length}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red)),
                        const Text('Error Rows (Repair Below)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Error Repair Table if any
        if (errors.isNotEmpty) ...[
          Text(
            '⚠️ Problematic Records (${errors.length} rows) — Click any cell with an edit icon to correct:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade700),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.red.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.red.withValues(alpha: 0.1)),
                    columns: [
                      const DataColumn(label: Text('Validation Reason', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
                      ..._dbFields.where((f) => f != '(ignore)').map((f) => DataColumn(label: Text(_dbFieldLabels[f]!, style: const TextStyle(fontWeight: FontWeight.bold)))),
                    ],
                    rows: errors.map((e) {
                      final mapped = e['mapped'] as Map<String, dynamic>;
                      return DataRow(
                        cells: [
                          DataCell(Text(e['error'].toString(), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12))),
                          ..._dbFields.where((f) => f != '(ignore)').map((f) => DataCell(
                                Text(mapped[f]?.toString() ?? ''),
                                showEditIcon: true,
                                onTap: () => _editCell(e, f, mapped[f]?.toString() ?? ''),
                              )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Re-validate Repaired Rows'),
              onPressed: () {
                _pickedFile = PlatformFile(name: 'edited.csv', size: 0, bytes: utf8.encode(_generateEditedCsv()));
                _mapping = {for (var f in _dbFields.where((x) => x != '(ignore)')) f: f};
                _runPreview();
              },
            ),
          ),
        ] else ...[
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_rounded, size: 64, color: Colors.green),
                  SizedBox(height: 12),
                  Text('All rows passed schema verification!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(height: 4),
                  Text('No syntax or duplicate errors detected. Ready to commit into electoral rolls.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),

        // Action toolbar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('Back to Mapping'),
            ),
            LoadingButton(
              label: 'Commit & Import ${valid.length} Valid Voters',
              icon: Icons.file_download_done_rounded,
              isLoading: _isImporting,
              onPressed: valid.isEmpty && errors.isNotEmpty ? null : _runImport,
              fullWidth: false,
            ),
          ],
        ),
      ],
    );
  }

  void _editCell(Map<String, dynamic> rowObj, String field, String currentValue) {
    final ctrl = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit ${_dbFieldLabels[field]}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextFormField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _dbFieldLabels[field],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              setState(() {
                final mapped = rowObj['mapped'] as Map<String, dynamic>;
                mapped[field] = ctrl.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save Cell'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // STEP 4: IMPORT COMPLETE
  // ══════════════════════════════════════════════════════════════════
  Widget _buildStepDone(bool isDark) {
    if (_importResult == null) return const SizedBox.shrink();

    final imported = _importResult!['imported'] ?? 0;
    final skipped = _importResult!['skipped'] ?? 0;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, size: 64, color: Colors.green),
          ),
          const SizedBox(height: 20),
          const Text('Voter Roll Import Complete!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'The voters have been enrolled and are ready for preliminary roll publication.',
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey.shade600),
          ),
          const SizedBox(height: 24),

          // Statistics Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceVariant : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatColumn('Successfully Imported', '$imported', Colors.green),
                const SizedBox(width: 40),
                Container(width: 1, height: 40, color: Colors.grey.shade300),
                const SizedBox(width: 40),
                _buildStatColumn('Skipped / Duplicates', '$skipped', Colors.orange),
              ],
            ),
          ),
          const SizedBox(height: 32),

          FilledButton.icon(
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Return to Voter Roll Management'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
