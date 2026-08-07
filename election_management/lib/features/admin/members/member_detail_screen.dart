import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/models.dart';

class MemberDetailScreen extends ConsumerWidget {
  final String memberId;
  const MemberDetailScreen({super.key, required this.memberId});

  Widget _buildSectionCard({required BuildContext context, required String title, required IconData icon, required List<Widget> children}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value.isNotEmpty ? value : 'N/A', style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(membersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Member Profile')),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (members) {
          final member = members.firstWhere((m) => m.id == memberId, orElse: () => throw Exception('Member not found'));

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Card
                    Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: AppColors.primaryDark,
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: AppColors.primaryLight,
                              backgroundImage: member.photoUrl.isNotEmpty
                                  ? NetworkImage(member.photoUrl)
                                  : null,
                              child: member.photoUrl.isEmpty
                                  ? const Icon(Icons.person, size: 40, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member.fullName,
                                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    member.email,
                                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                                  ),
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: member.membershipStatus.toLowerCase() == 'active' ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: member.membershipStatus.toLowerCase() == 'active' ? Colors.green : Colors.orange),
                                    ),
                                    child: Text(
                                      member.membershipStatus.toUpperCase(),
                                      style: TextStyle(
                                        color: member.membershipStatus.toLowerCase() == 'active' ? Colors.greenAccent : Colors.orangeAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Details
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildSectionCard(
                            context: context,
                            title: 'Organization Info',
                            icon: Icons.work_outline_rounded,
                            children: [
                              _buildField('Member ID', member.memberCode),
                              _buildField('Position Title', member.positionTitle),
                              _buildField('Department', member.department),
                              _buildField('Region', member.region),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            children: [
                              _buildSectionCard(
                                context: context,
                                title: 'Contact & Demographics',
                                icon: Icons.contact_mail_outlined,
                                children: [
                                  _buildField('Phone Number', member.phone),
                                  _buildField('Gender', member.gender),
                                ],
                              ),
                              _buildSectionCard(
                                context: context,
                                title: 'Election Privileges',
                                icon: Icons.how_to_vote_outlined,
                                children: [
                                  _buildField('Voting Weight', member.votingWeight.toString()),
                                  _buildField('Eligible to Vote', member.isEligibleToVote ? 'Yes' : 'No'),
                                  _buildField('Eligible to Nominate', member.isEligibleToNominate ? 'Yes' : 'No'),
                                  _buildField('Membership Expiry', member.membershipExpiryDate ?? 'No Expiry'),
                                ],
                              ),
                            ],
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
    );
  }
}
