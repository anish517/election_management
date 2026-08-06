import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/app_providers.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/models/models.dart';

class NominationScreen extends ConsumerStatefulWidget {
  final String electionId;
  const NominationScreen({super.key, required this.electionId});

  @override
  ConsumerState<NominationScreen> createState() => _NominationScreenState();
}

class _NominationScreenState extends ConsumerState<NominationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _manifestoController = TextEditingController();
  final _slateController = TextEditingController();
  String? _selectedPositionId;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _manifestoController.dispose();
    _slateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPositionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a position.')));
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(ApiConstants.electionCandidates(widget.electionId), data: {
        'position': _selectedPositionId,
        'manifesto': _manifestoController.text.trim(),
        'slate_name': _slateController.text.trim(),
        'election': widget.electionId,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nomination submitted successfully!')));
      }
    } on DioException catch (e) {
      final msg = (e.response?.data is Map)
          ? e.response?.data['error'] ?? 'Submission failed'
          : 'Submission failed';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final electionAsync = ref.watch(electionProvider(widget.electionId));

    return Scaffold(
      appBar: AppBar(title: const Text('Self Nomination')),
      body: electionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (election) {
          if (election.positions.isEmpty) {
            return const Center(child: Text('No positions available to nominate for.'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Apply for Candidacy',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Fill out the form below to submit your nomination for this election.'),
                  const SizedBox(height: 24),
                  
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Position'),
                    value: _selectedPositionId,
                    items: election.positions.map((p) {
                      return DropdownMenuItem(value: p.id, child: Text(p.title));
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedPositionId = val),
                    validator: (val) => val == null ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _manifestoController,
                    decoration: const InputDecoration(
                      labelText: 'Manifesto / Statement',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 5,
                    validator: (val) =>
                        val == null || val.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _slateController,
                    decoration: const InputDecoration(
                      labelText: 'Slate / Party Name (Optional)',
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  LoadingButton(
                    onPressed: _submit,
                    isLoading: _isSubmitting,
                    label: 'Submit Nomination',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
