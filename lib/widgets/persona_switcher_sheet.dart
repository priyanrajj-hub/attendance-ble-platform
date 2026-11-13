import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/user_role.dart';
import '../providers/auth_provider.dart';

/// Interactive modal sheet to switch between Student, Faculty, and Admin personas on the fly.
void showPersonaSwitcherModal(BuildContext context, WidgetRef ref) {
  final currentProfile = ref.read(userProfileProvider).value;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.swap_horizontal_circle_outlined, color: Color(0xFF283593), size: 28),
                const SizedBox(width: 10),
                Text(
                  'Multi-Role Persona Switcher',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF283593),
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Switch between institutional roles instantly for full-system field verification.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _PersonaOptionCard(
              title: 'Student: PRIYANRAJ J',
              subtitle: 'BLE radar scan, biometric binding, 82% attendance',
              icon: Icons.school,
              badgeColor: Colors.indigo,
              isSelected: currentProfile?.role == UserRole.student,
              onTap: () {
                Navigator.of(ctx).pop();
                ref.read(demoProfileProvider.notifier).state = DemoPersonas.student;
                ctx.go('/student');
              },
            ),
            const SizedBox(height: 10),
            _PersonaOptionCard(
              title: 'Faculty: Dr. Rajesh Kumar',
              subtitle: 'Broadcast CSE450 beacon, live student roster, presence radar',
              icon: Icons.sensors,
              badgeColor: Colors.teal,
              isSelected: currentProfile?.role == UserRole.faculty,
              onTap: () {
                Navigator.of(ctx).pop();
                ref.read(demoProfileProvider.notifier).state = DemoPersonas.faculty;
                ctx.go('/faculty');
              },
            ),
            const SizedBox(height: 10),
            _PersonaOptionCard(
              title: 'Administrator: Chief Admin',
              subtitle: 'Institutional audit log, pending queue, student verification',
              icon: Icons.verified_user,
              badgeColor: Colors.deepOrange,
              isSelected: currentProfile?.role == UserRole.admin,
              onTap: () {
                Navigator.of(ctx).pop();
                ref.read(demoProfileProvider.notifier).state = DemoPersonas.admin;
                ctx.go('/admin');
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Exit Demo / Sign Out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade300),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await ref.read(authControllerProvider.notifier).signOut();
                if (ctx.mounted) ctx.go('/login');
              },
            ),
          ],
        ),
      );
    },
  );
}

class _PersonaOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color badgeColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _PersonaOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badgeColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? badgeColor.withOpacity(0.08) : Colors.grey.shade50,
          border: Border.all(
            color: isSelected ? badgeColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: badgeColor.withOpacity(0.15),
              foregroundColor: badgeColor,
              child: Icon(icon, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isSelected ? badgeColor : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: badgeColor, size: 22)
            else
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
