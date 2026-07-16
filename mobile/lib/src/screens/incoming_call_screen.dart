import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final caller = state.incomingCaller;
    final call = state.incomingCall;
    final isVideo = call?['type'] == 'VIDEO';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 52,
                  backgroundColor: Colors.white24,
                  child: Text(
                    (caller?.name ?? '?').characters.first,
                    style: const TextStyle(color: Colors.white, fontSize: 36),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  caller?.name ?? 'Incoming call',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isVideo ? 'Video call' : 'Audio call',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filled(
                      tooltip: 'Reject',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        fixedSize: const Size.square(64),
                      ),
                      onPressed: state.rejectIncomingCall,
                      icon: const Icon(Icons.call_end, size: 30),
                    ),
                    const SizedBox(width: 36),
                    IconButton.filled(
                      tooltip: 'Accept',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        fixedSize: const Size.square(64),
                      ),
                      onPressed: state.acceptIncomingCall,
                      icon: const Icon(Icons.call, size: 30),
                    ),
                  ],
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    state.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
