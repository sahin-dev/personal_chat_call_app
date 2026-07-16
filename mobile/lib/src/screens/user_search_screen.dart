import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().searchUsers('');
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('New conversation')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SearchBar(
              controller: _controller,
              autoFocus: true,
              hintText: 'Search by name or email',
              leading: const Icon(Icons.search),
              trailing: [
                if (_query.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear search',
                    onPressed: _clear,
                    icon: const Icon(Icons.close),
                  ),
              ],
              onChanged: _onChanged,
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _results(state)),
        ],
      ),
    );
  }

  Widget _results(AppState state) {
    if (_query.trim().isEmpty) {
      return const _SearchEmpty(
        icon: Icons.person_search_outlined,
        title: 'Find someone',
        detail: 'Search by their name or email address.',
      );
    }
    if (state.searchingUsers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.userResults.isEmpty) {
      return const _SearchEmpty(
        icon: Icons.search_off,
        title: 'No users found',
        detail: 'Try a different name or email address.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.userResults.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
      itemBuilder: (context, index) {
        final user = state.userResults[index];
        final online = state.isUserOnline(user.id);
        return ListTile(
          minVerticalPadding: 12,
          leading: UserAvatar(user: user, online: online),
          title: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            online ? 'Online' : user.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: online ? TextStyle(color: Colors.green.shade700) : null,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openUser(user),
        );
      },
    );
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) context.read<AppState>().searchUsers(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
    context.read<AppState>().searchUsers('');
  }

  Future<void> _openUser(AppUser user) async {
    final state = context.read<AppState>();
    await state.openDirectChat(user);
    if (!mounted || state.activeChat == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChatScreen()),
    );
  }
}

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
