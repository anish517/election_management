import 'package:election_management/features/admin/members/edit_member_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/admin_providers.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/widgets/admin_drawer.dart';
import '../../../shared/widgets/shimmer_loaders.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/responsive_layout.dart';
import 'csv_import_wizard_screen.dart';

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
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export CSV',
            onPressed: () async {
              final token = await JwtInterceptor.getAccessToken();
              final url = Uri.parse(
                '${ApiConstants.baseUrl}${ApiConstants.members}export_csv/?token=$token',
              );
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not launch export URL'),
                    ),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: 'Import CSV Wizard',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CsvImportWizardScreen()),
              );
              ref.invalidate(membersProvider);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(membersProvider),
          ),
        ],
      ),
      body: membersAsync.when(
        loading: () => const ListSkeleton(count: 7),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 40,
              ),
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
            return const EmptyStateWidget(
              icon: Icons.people_alt_outlined,
              title: 'No Members Yet',
              subtitle: 'Import a CSV or add members to get started.',
            );
          }
          return ResponsivePageWrapper(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(membersProvider),
              child: GridView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: members.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 450,
                mainAxisExtent: 110,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemBuilder: (context, i) {
                final m = members[i];
                final isDark = Theme.of(context).brightness == Brightness.dark;
                
                return Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surface : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05),
                    ),
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: m.photoUrl.isNotEmpty
                      ? CircleAvatar(
                          backgroundImage: NetworkImage(m.photoUrl),
                        )
                      : CircleAvatar(
                          backgroundColor: AppColors.primaryLight.withValues(
                            alpha: 0.2,
                          ),
                          child: const Icon(
                            Icons.person,
                            color: AppColors.primaryLight,
                          ),
                        ),
                  title: Text(m.fullName),
                  subtitle: Text('${m.email} \n${m.membershipStatus}'),
                  isThreeLine: true,
                  onTap: () => context.pushNamed(
                    'member-detail',
                    pathParameters: {'memberId': m.id},
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Member',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          color: AppColors.textMuted,
                        ),
                        onSelected: (val) async {
                          if (val == 'edit') {
                            showDialog(
                              context: context,
                              builder: (_) => EditMemberDialog(member: m),
                            );
                          } else if (val == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Member?'),
                                content: const Text(
                                  'Are you sure you want to delete this member?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.error,
                                    ),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true && context.mounted) {
                              try {
                                await ref
                                    .read(addMemberProvider.notifier)
                                    .deleteMember(m.id);
                                if (context.mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Member deleted'),
                                    ),
                                  );
                              } catch (e) {
                                if (context.mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                              }
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              'Delete',
                              style: TextStyle(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
              },
            ),
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
