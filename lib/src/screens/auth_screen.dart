import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _registering = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 48 - bottomInset)
                    .clamp(0, double.infinity),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _BrandHeader(),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<bool>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  icon: Icon(Icons.login),
                                  label: Text('Sign in'),
                                ),
                                ButtonSegment(
                                  value: true,
                                  icon: Icon(Icons.person_add_outlined),
                                  label: Text('Register'),
                                ),
                              ],
                              selected: {_registering},
                              onSelectionChanged: state.loading
                                  ? null
                                  : (selection) => _changeMode(selection.first),
                            ),
                          ),
                          const SizedBox(height: 28),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: Text(
                              _registering
                                  ? 'Create your account'
                                  : 'Welcome back',
                              key: ValueKey(_registering),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _registering
                                ? 'Enter your details to start messaging.'
                                : 'Sign in to continue your conversations.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 24),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: _registering
                                ? Column(
                                    children: [
                                      TextFormField(
                                        controller: _nameController,
                                        enabled: !state.loading,
                                        textCapitalization:
                                            TextCapitalization.words,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [
                                          AutofillHints.name
                                        ],
                                        decoration: const InputDecoration(
                                          labelText: 'Name',
                                          prefixIcon:
                                              Icon(Icons.person_outline),
                                        ),
                                        validator: _validateName,
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                          TextFormField(
                            controller: _emailController,
                            enabled: !state.loading,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            enabled: !state.loading,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: _registering
                                ? const [AutofillHints.newPassword]
                                : const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: state.loading
                                    ? null
                                    : () => setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
                                        ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: _validatePassword,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (state.error != null) ...[
                            const SizedBox(height: 16),
                            _ErrorMessage(
                                message: _friendlyError(state.error!)),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: state.loading ? null : _submit,
                              icon: state.loading
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _registering
                                          ? Icons.person_add_outlined
                                          : Icons.login,
                                    ),
                              label: Text(
                                state.loading
                                    ? 'Please wait'
                                    : _registering
                                        ? 'Create account'
                                        : 'Sign in',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _changeMode(bool registering) {
    context.read<AppState>().clearError();
    setState(() {
      _registering = registering;
      _obscurePassword = true;
    });
    _formKey.currentState?.reset();
  }

  Future<void> _submit() async {
    if (context.read<AppState>().loading ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    final state = context.read<AppState>();
    if (_registering) {
      await state.register(
        _nameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text,
      );
    } else {
      await state.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
    }
  }

  String? _validateName(String? value) {
    if (!_registering) return null;
    if ((value ?? '').trim().length < 2) return 'Enter at least 2 characters';
    return null;
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    return valid ? null : 'Enter a valid email address';
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').length < 6) return 'Use at least 6 characters';
    return null;
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SizedBox.square(
            dimension: 64,
            child: Icon(
              Icons.forum_rounded,
              size: 34,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Chat Call',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Messages and calls, together.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colors.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _friendlyError(String error) {
  try {
    final decoded = jsonDecode(error);
    if (decoded is Map<String, dynamic>) {
      final message = decoded['message'];
      if (message is String) return message;
      if (message is List) return message.whereType<String>().join('\n');
    }
  } catch (_) {
    // The API may return a plain-text error.
  }
  return error;
}
