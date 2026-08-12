import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/widgets/glass_card.dart';

class GuidelinesScreen extends ConsumerStatefulWidget {
  final String electionId;
  const GuidelinesScreen({super.key, required this.electionId});

  @override
  ConsumerState<GuidelinesScreen> createState() => _GuidelinesScreenState();
}

class _GuidelinesScreenState extends ConsumerState<GuidelinesScreen> {
  final _guidelinesController = TextEditingController();
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchGuidelines();
  }

  @override
  void dispose() {
    _guidelinesController.dispose();
    super.dispose();
  }

  Future<void> _fetchGuidelines() async {
    try {
      final dio = ref.read(apiClientProvider);
      final url = ApiConstants.electionDetail(widget.electionId);
      final response = await dio.get(url);
      
      if (mounted) {
        setState(() {
          _guidelinesController.text = response.data['guidelines'] ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveGuidelines() async {
    setState(() => _isSaving = true);
    
    try {
      final dio = ref.read(apiClientProvider);
      final url = ApiConstants.electionDetail(widget.electionId);
      await dio.patch(
        url,
        data: {'guidelines': _guidelinesController.text},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guidelines saved successfully!')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save guidelines: ${e.response?.data ?? e.message}')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Election Guidelines',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Provide the rules, terms, and guidelines for this election.',
                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 16),
              ),
              const SizedBox(height: 32),
              
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _guidelinesController,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            labelText: 'Guidelines (Markdown supported)',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveGuidelines,
                          icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded),
                          label: Text(_isSaving ? 'Saving...' : 'Save Guidelines'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
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
      ),
    );
  }
}
