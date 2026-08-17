import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/image_upload_widget.dart';
import '../../../core/theme/app_theme.dart';

class EditCandidateDialog extends ConsumerStatefulWidget {
  final String electionId;
  final CandidateModel candidate;
  const EditCandidateDialog({super.key, required this.electionId, required this.candidate});

  @override
  ConsumerState<EditCandidateDialog> createState() => _EditCandidateDialogState();
}

class _EditCandidateDialogState extends ConsumerState<EditCandidateDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _manifestoController;
  late TextEditingController _personalDescController;
  late TextEditingController _contributionController;
  late String _status;
  String _photoUrl = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _manifestoController = TextEditingController(text: widget.candidate.manifesto);
    _personalDescController = TextEditingController(text: widget.candidate.personalDescription);
    _contributionController = TextEditingController(text: widget.candidate.contributionToOrg);
    _status = widget.candidate.status ?? 'pending';
    _photoUrl = widget.candidate.photoUrl ?? (widget.candidate.candidateImage ?? '');
  }

  @override
  void dispose() {
    _manifestoController.dispose();
    _personalDescController.dispose();
    _contributionController.dispose();
    super.dispose();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'verified':
        return Colors.green;
      case 'rejected':
      case 'disqualified':
        return Colors.red;
      case 'withdrawn':
        return Colors.grey.shade600;
      case 'pending':
      case 'draft':
      default:
        return Colors.amber.shade800;
    }
  }

  String _formatStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return 'Approved (स्वीकृत)';
      case 'rejected':
        return 'Rejected (अस्वीकृत)';
      case 'withdrawn':
        return 'Withdrawn (फिर्ता)';
      case 'pending':
      default:
        return 'Pending Review (छानबिनमा)';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final dio = ref.read(apiClientProvider);
      await dio.patch(
        '${ApiConstants.electionCandidates(widget.electionId)}${widget.candidate.id}/',
        data: {
          'manifesto': _manifestoController.text.trim(),
          'personal_description': _personalDescController.text.trim(),
          'contribution_to_org': _contributionController.text.trim(),
          'status': _status,
          'photo_url': _photoUrl,
          'candidate_image': _photoUrl,
        },
      );
      ref.invalidate(electionProvider(widget.electionId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text('Candidate "${widget.candidate.name}" updated successfully!'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update candidate: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _dec(
    String label, {
    String? hint,
    Widget? prefix,
    String? helper,
    bool isDark = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      prefixIcon: prefix,
      filled: true,
      fillColor: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.5) : const Color(0xFFF9FAFB),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _getStatusColor(_status);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? AppColors.surface : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 860),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dialog Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit_note_rounded, color: AppColors.primaryLight, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Candidate Profile (उम्मेदवार सम्पादन)',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Modify nomination status, platform manifesto, and profile credentials.',
                          style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Form Scrollable Body
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    children: [
                      // Candidate Hero Profile Card
                      Material(
                        color: isDark ? AppColors.surfaceVariant.withValues(alpha: 0.4) : const Color(0xFFF8FAFC),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ImageUploadWidget(
                                initialImageUrl: _photoUrl,
                                placeholderText: widget.candidate.name.isNotEmpty
                                    ? widget.candidate.name[0].toUpperCase()
                                    : 'C',
                                radius: 36,
                                onImageUploaded: (url) => setState(() => _photoUrl = url),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.candidate.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        if (widget.candidate.positionTitle != null && widget.candidate.positionTitle!.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              widget.candidate.positionTitle!,
                                              style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ),
                                        if (widget.candidate.quotaName != null && widget.candidate.quotaName!.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Quota: ${widget.candidate.quotaName}',
                                              style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.w600, fontSize: 11),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (widget.candidate.email != null && widget.candidate.email!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.candidate.email!,
                                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Scrutiny Status Selector
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nomination Scrutiny Status (उम्मेदवारी स्थिति) *',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _status,
                            decoration: _dec(
                              'Candidacy Status',
                              prefix: Icon(Icons.verified_rounded, color: statusColor),
                              isDark: isDark,
                            ),
                            items: ['approved', 'pending', 'rejected', 'withdrawn'].map((st) {
                              final color = _getStatusColor(st);
                              return DropdownMenuItem(
                                value: st,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      _formatStatusLabel(st),
                                      style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _status = v);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Personal Description
                      TextFormField(
                        controller: _personalDescController,
                        decoration: _dec(
                          'Personal Description & Qualifications',
                          hint: 'Biographical summary...',
                          prefix: const Icon(Icons.person_outline_rounded),
                          isDark: isDark,
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),

                      // Contribution to Organization
                      TextFormField(
                        controller: _contributionController,
                        decoration: _dec(
                          'Contributions to Organization',
                          hint: 'Past service, committee work, leadership...',
                          prefix: const Icon(Icons.handshake_outlined),
                          isDark: isDark,
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),

                      // Manifesto / Platform
                      TextFormField(
                        controller: _manifestoController,
                        decoration: _dec(
                          'Election Manifesto & Commitments *',
                          hint: 'Platform manifesto and vision statements...',
                          prefix: const Icon(Icons.menu_book_rounded),
                          isDark: isDark,
                        ),
                        maxLines: 4,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Manifesto is required' : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isLoading ? null : () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 14),
                  LoadingButton(
                    isLoading: _isLoading,
                    label: 'Save Changes',
                    icon: Icons.check_circle_outline_rounded,
                    onPressed: _submit,
                    fullWidth: false,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
