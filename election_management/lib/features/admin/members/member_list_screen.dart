import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../../shared/widgets/admin_drawer.dart';

class MemberListScreen extends ConsumerWidget {
  const MemberListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(membersProvider);

    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: 'Import CSV',
            onPressed: () async {
              try {
                // We'll use file_picker to get the file
                final result = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['csv'],
                  withData: true,
                );
                
                if (result != null && result.files.single.bytes != null) {
                  // Show loading
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Uploading CSV...'))
                    );
                  }
                  
                  final fileBytes = result.files.single.bytes!;
                  final fileName = result.files.single.name;
                  final dio = ref.read(apiClientProvider);
                  
                  final formData = FormData.fromMap({
                    'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
                  });
                  
                  final resp = await dio.post(ApiConstants.members + 'import_csv/', data: formData);
                  
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(resp.data['message'] ?? 'Import successful!'))
                    );
                    ref.invalidate(membersProvider);
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Import failed: $e'))
                  );
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(membersProvider),
          ),
        ],
      ),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
              const SizedBox(height: 12),
              Text('Failed to load members\n$e', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.invalidate(membersProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (members) {
          if (members.isEmpty) {
            return const Center(child: Text('No members found.'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(membersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: members.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final m = members[i];
                return ListTile(
                  tileColor: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.surfaceVariant)),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primaryLight.withValues(alpha: 0.2),
                    child: const Icon(Icons.person, color: AppColors.primaryLight),
                  ),
                  title: Text(m.fullName),
                  subtitle: Text('${m.email} \n${m.membershipStatus}'),
                  isThreeLine: true,
                  onTap: () => context.pushNamed('member-detail', pathParameters: {'memberId': m.id}),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Member',
                      style: const TextStyle(color: AppColors.accent, fontSize: 10),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed('add-member'),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Member'),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}
