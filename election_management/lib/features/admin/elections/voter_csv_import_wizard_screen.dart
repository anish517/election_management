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
    'voter_id', 'prefix', 'first_name', 'middle_name', 'last_name', 
    'email', 'phone', 'council_number', 'citizenship_number', '(ignore)'
  ];

  static const _dbFieldLabels = {
    'voter_id': 'Voter ID',
    'prefix': 'Prefix (Mr/Ms)',
    'first_name': 'First Name *',
    'middle_name': 'Middle Name',
    'last_name': 'Last Name *',
    'email': 'Email',
    'phone': 'Phone',
    'council_number': 'Council Number',
    'citizenship_number': 'Citizenship Number',
    '(ignore)': '— Ignore this column —',
  };

  String _autoMap(String col) {
    final c = col.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (c.contains('email')) return 'email';
    if (c.contains('first')) return 'first_name';
    if (c.contains('last')) return 'last_name';
    if (c.contains('middle')) return 'middle_name';
    if (c.contains('name')) return 'first_name'; 
    if (c.contains('voter') || c == 'id' || c.endsWith('id') || c.contains('code')) return 'voter_id';
    if (c.contains('phone') || c.contains('mobile')) return 'phone';
    if (c.contains('council')) return 'council_number';
    if (c.contains('citizen')) return 'citizenship_number';
    if (c.contains('prefix')) return 'prefix';
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preview failed: $e')));
    } finally {
      setState(() => _isPreviewing = false);
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
          setState(() { _importResult = resp.data; _step = 3; });
      } else {
          final formData = FormData.fromMap({
            'file': MultipartFile.fromBytes(_pickedFile!.bytes!, filename: _pickedFile!.name),
            'mapping': jsonEncode(_mapping),
          });
          final resp = await dio.post(ApiConstants.importElectionVotersCsv(widget.electionId), data: formData);
          ref.invalidate(votersProvider(widget.electionId));
          setState(() { _importResult = resp.data; _step = 3; });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      setState(() => _isImporting = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Voters CSV'),
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
      body: Stepper(
        type: StepperType.horizontal,
        currentStep: _step > 3 ? 3 : _step,
        controlsBuilder: (context, details) => const SizedBox.shrink(),
        steps: [
          Step(
            title: const Text('Upload'),
            isActive: _step >= 0,
            state: _step > 0 ? StepState.complete : StepState.indexed,
            content: _buildStepUpload(),
          ),
          Step(
            title: const Text('Map'),
            isActive: _step >= 1,
            state: _step > 1 ? StepState.complete : StepState.indexed,
            content: _buildStepMap(),
          ),
          Step(
            title: const Text('Review'),
            isActive: _step >= 2,
            state: _step > 2 ? StepState.complete : StepState.indexed,
            content: _buildStepPreview(),
          ),
          Step(
            title: const Text('Done'),
            isActive: _step >= 3,
            state: _step == 3 ? StepState.complete : StepState.indexed,
            content: _buildStepDone(),
          ),
        ],
      ),
    );
  }

  void _downloadTemplate() {
    final header = "voter_id,prefix,first_name,middle_name,last_name,email,phone,council_number,citizenship_number\n";
    final bytes = utf8.encode(header);
    final base64String = base64Encode(bytes);
    
    try {
      downloadFileFromBase64(base64String, 'voters_template.csv');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not download template: $e')));
      }
    }
  }

  Widget _buildStepUpload() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.upload_file_rounded, size: 64, color: AppColors.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('Upload a CSV file containing voter records.', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download Template'),
                  onPressed: _downloadTemplate,
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.file_open_rounded),
                  label: const Text('Select CSV File'),
                  onPressed: _pickFile,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepMap() {
    if (_pickedFile == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Map your CSV columns to the database fields.', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          height: 350,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
          child: ListView.separated(
            itemCount: _mapping.keys.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final csvCol = _mapping.keys.elementAt(i);
              final currentMap = _mapping[csvCol];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(csvCol, style: const TextStyle(fontWeight: FontWeight.w500))),
                    const Icon(Icons.arrow_right_alt_rounded, color: Colors.grey),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: currentMap,
                        items: _dbFields.map((f) => DropdownMenuItem(value: f, child: Text(_dbFieldLabels[f]!))).toList(),
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
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: LoadingButton(
            label: 'Next: Preview',
            isLoading: _isPreviewing,
            onPressed: _runPreview,
          ),
        ),
      ],
    );
  }

  Widget _buildStepPreview() {
    if (_preview == null) return const SizedBox.shrink();
    final valid = _preview!.validRows;
    final errors = _preview!.errorRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Card(
                color: Colors.green.shade50,
                child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [Text('${valid.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)), const Text('Valid Rows')])),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Card(
                color: Colors.red.shade50,
                child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [Text('${errors.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red)), const Text('Error Rows')])),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        if (errors.isNotEmpty) ...[
            const Text('Errors (Click a cell to edit and fix):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 8),
            Container(
              height: 250,
              decoration: BoxDecoration(border: Border.all(color: Colors.red.shade200), borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: [
                      const DataColumn(label: Text('Error', style: TextStyle(color: Colors.red))),
                      ..._dbFields.where((f) => f != '(ignore)').map((f) => DataColumn(label: Text(_dbFieldLabels[f]!))),
                    ],
                    rows: errors.map((e) {
                      final mapped = e['mapped'] as Map<String, dynamic>;
                      return DataRow(
                        cells: [
                          DataCell(Text(e['error'].toString(), style: const TextStyle(color: Colors.red))),
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
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Re-validate Edits'),
                onPressed: () {
                    _pickedFile = PlatformFile(name: 'edited.csv', size: 0, bytes: utf8.encode(_generateEditedCsv()));
                    _mapping = {for (var f in _dbFields.where((x) => x != '(ignore)')) f: f}; 
                    _runPreview();
                },
              ),
            ),
            const Divider(height: 32),
        ],

        Align(
          alignment: Alignment.centerRight,
          child: LoadingButton(
            label: 'Import ${valid.length} Valid Rows',
            isLoading: _isImporting,
            onPressed: valid.isEmpty && errors.isNotEmpty ? null : _runImport,
          ),
        ),
      ],
    );
  }

  void _editCell(Map<String, dynamic> rowObj, String field, String currentValue) {
      final ctrl = TextEditingController(text: currentValue);
      showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
              title: Text('Edit ${_dbFieldLabels[field]}'),
              content: TextFormField(controller: ctrl, autofocus: true),
              actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                          setState(() {
                              final mapped = rowObj['mapped'] as Map<String, dynamic>;
                              mapped[field] = ctrl.text;
                          });
                          Navigator.pop(ctx);
                      },
                      child: const Text('Save'),
                  ),
              ],
          )
      );
  }

  Widget _buildStepDone() {
    if (_importResult == null) return const SizedBox.shrink();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.check_circle_rounded, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            const Text('Import Complete', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('Successfully imported: ${_importResult!['imported']}'),
            Text('Skipped: ${_importResult!['skipped']}'),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Finish'),
            ),
          ],
        ),
      ),
    );
  }
}
