import 'package:flutter/material.dart';

import '../models.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    required this.online,
    this.radius = 24,
  });

  final AppUser? user;
  final bool online;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final name = user?.name.trim() ?? '';
    return SizedBox.square(
      dimension: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            foregroundImage:
                user?.avatarUrl == null ? null : NetworkImage(user!.avatarUrl!),
            child: Text(
              name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
              style: TextStyle(
                fontSize: radius * 0.72,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        online ? Colors.green.shade600 : Colors.grey.shade500,
                  ),
                  child: const SizedBox.square(dimension: 10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
