import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../core/providers/app_providers.dart';
import '../../core/network/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/widgets/image_upload_widget.dart';
import '../../shared/models/models.dart';
import '../candidates/nomination_list_screen.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';

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
  String _photoUrl = '';
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
        'photo_url': _photoUrl,
        'election': widget.electionId,
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nomination submitted successfully!')));
      }
    } on DioException catch (e) {
      String msg = 'Submission failed';
      if (e.response?.data is Map) {
        final data = e.response!.data as Map;
        if (data.containsKey('error')) {
          msg = data['error'].toString();
        } else if (data.containsKey('non_field_errors')) {
          msg = (data['non_field_errors'] as List).join(', ');
        } else if (data.values.isNotEmpty) {
          msg = data.values.first.toString();
        }
      }
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

          final user = ref.watch(authProvider).user;
          final candidatesAsync = ref.watch(candidatesProvider(widget.electionId));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                candidatesAsync.when(
                  data: (candidates) {
                    final myNominations = candidates.where((c) => c.memberEmail == user?.email).toList();
                    if (myNominations.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My Nominations', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 12),
                        ...myNominations.map((c) => Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                title: Text(c.positionTitle ?? 'Position'),
                                subtitle: Text('Status: ${c.status?.toUpperCase() ?? 'PENDING'}\nManifesto: ${c.manifesto}'),
                                isThreeLine: true,
                                trailing: Icon(
                                  c.status == 'approved' ? Icons.check_circle_rounded :
                                  c.status == 'rejected' ? Icons.cancel_rounded : Icons.pending_rounded,
                                  color: c.status == 'approved' ? Colors.green :
                                         c.status == 'rejected' ? Colors.red : Colors.orange,
                                ),
                              ),
                            )),
                        const SizedBox(height: 32),
                        const Divider(),
                        const SizedBox(height: 32),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Apply for Candidacy',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Fill out the form below to submit your nomination for this election.'),
                  const SizedBox(height: 24),
                  
                  Center(
                    child: ImageUploadWidget(
                      initialImageUrl: _photoUrl,
                      placeholderText: 'PHOTO',
                      radius: 40,
                      onImageUploaded: (url) => setState(() => _photoUrl = url),
                    ),
                  ),
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
            ],
          ),
          );
        },
      ),
    );
  }
}
