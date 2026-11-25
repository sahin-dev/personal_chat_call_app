import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'src/app_state.dart';
import 'src/backend_ping_service.dart';
import 'src/push_notification_service.dart';
import 'src/screens/auth_screen.dart';
import 'src/screens/call_screen.dart';
import 'src/screens/home_screen.dart';
import 'src/screens/incoming_call_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  BackendPingService.instance.start();
  unawaited(PushNotificationService.instance.initialize());
  runApp(const ChatCallApp());
}

class ChatCallApp extends StatelessWidget {
  const ChatCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF087F73),
    );
    return BlocProvider(
      create: (_) => AppCubit(),
      child: MaterialApp(
        title: 'Chat Call',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: colorScheme,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF7F9F9),
          appBarTheme: AppBarTheme(
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        builder: (context, child) {
          final state = context.watch<AppCubit>().state;
          return Stack(
            fit: StackFit.expand,
            children: [
              child ?? const SizedBox.shrink(),
              if (state.activeCallId != null)
                const CallScreen()
              else if (state.incomingCall != null)
                const IncomingCallScreen(),
            ],
          );
        },
        home: const AppRoot(),
      ),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppCubit>().state;
    if (!state.sessionInitialized) return const _SessionLoadingScreen();
    return state.isAuthenticated ? const HomeScreen() : const AuthScreen();
  }
}

class _SessionLoadingScreen extends StatelessWidget {
  const _SessionLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_rounded, size: 48, color: colors.primary),
            const SizedBox(height: 20),
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
