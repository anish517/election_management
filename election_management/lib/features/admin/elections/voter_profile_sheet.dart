import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class VoterProfileSheet extends StatelessWidget {
  final Map<String, dynamic> voter;

  const VoterProfileSheet({super.key, required this.voter});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fullName = (voter['full_name'] as String?)?.trim() ?? 'Unknown';
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.background : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primaryLight.withValues(alpha: 0.2),
                child: Text(initial, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
              ),
              const SizedBox(height: 16),
              Text(fullName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Voter ID', voter['voter_id']?.toString(), Icons.badge, isDark),
                      _buildInfoRow('Email', voter['email']?.toString(), Icons.email, isDark),
                      _buildInfoRow('Phone', voter['phone']?.toString(), Icons.phone, isDark),
                      _buildInfoRow('Council Number', voter['council_number']?.toString(), Icons.account_balance, isDark),
                      _buildInfoRow('Citizenship Number', voter['citizenship_number']?.toString(), Icons.credit_card, isDark),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String? value, IconData icon, bool isDark) {
    if (value == null || value.isEmpty || value == '-') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600])),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
