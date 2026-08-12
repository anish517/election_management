import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../core/theme/app_theme.dart';

class AddPositionDialog extends ConsumerStatefulWidget {
  final String electionId;
  const AddPositionDialog({super.key, required this.electionId});

  @override
  ConsumerState<AddPositionDialog> createState() => _AddPositionDialogState();
}

class _AddPositionDialogState extends ConsumerState<AddPositionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _quotaController = TextEditingController();
  final _seatsController = TextEditingController(text: '1');
  final _resultOrderController = TextEditingController(text: '0');
  final _chargeController = TextEditingController(text: '0.00');
  
  String _votingMethod = 'fptp';
  String _bgColor = '#563d7c';
  bool _isLoading = false;

  final List<String> _colors = ['#563d7c', '#1ac6ff', '#e6190a', '#afee11', '#ffa500', '#2d3436'];

  @override
  void dispose() {
    _titleController.dispose();
    _quotaController.dispose();
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
      await dio.post(ApiConstants.electionPositions(widget.electionId), data: {
        'title': _titleController.text.trim(),
        'quota_name': _quotaController.text.trim(),
        'seats_available': int.parse(_seatsController.text),
        'result_order': int.parse(_resultOrderController.text),
        'nominee_charge': double.parse(_chargeController.text),
        'bg_color': _bgColor,
        'voting_method': _votingMethod,
      });
      ref.invalidate(electionProvider(widget.electionId));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Add Designation', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
                  ],
                ),
                const Divider(height: 24),
                
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Designation Name *', hintText: 'e.g. President'),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quotaController,
                        decoration: const InputDecoration(labelText: 'Quota (Optional)', hintText: 'e.g. Female, Dalit'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _seatsController,
                        decoration: const InputDecoration(labelText: 'Quota / Seats *'),
                        keyboardType: TextInputType.number,
                        validator: (v) => int.tryParse(v ?? '') == null ? 'Invalid' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _resultOrderController,
                        decoration: const InputDecoration(labelText: 'Result Order', helperText: 'Lower numbers appear first'),
                        keyboardType: TextInputType.number,
                        validator: (v) => int.tryParse(v ?? '') == null ? 'Invalid' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _chargeController,
                        decoration: const InputDecoration(labelText: 'Nominee Charge (Rs.)'),
                        keyboardType: TextInputType.number,
                        validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                const Text('Background Color', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _colors.map((c) {
                    final isSelected = _bgColor == c;
                    return InkWell(
                      onTap: () => setState(() => _bgColor = c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _hexToColor(c),
                          shape: BoxShape.circle,
                          border: Border.all(color: isSelected ? Colors.black : Colors.transparent, width: 3),
                        ),
                        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                      ),
                    );
                  }).toList(),
                ),
                
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  value: _votingMethod,
                  decoration: const InputDecoration(labelText: 'Voting Method'),
                  items: const [
                    DropdownMenuItem(value: 'fptp', child: Text('First Past The Post')),
                    DropdownMenuItem(value: 'multi_choice', child: Text('Multiple Choice (Block)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _votingMethod = v);
                  },
                ),
                
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : () => context.pop(),
                      child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                    ),
                    const SizedBox(width: 16),
                    LoadingButton(
                      isLoading: _isLoading,
                      onPressed: _submit,
                      label: 'Save Designation',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
