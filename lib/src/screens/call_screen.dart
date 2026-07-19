import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _micEnabled = true;
  bool _cameraEnabled = true;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hasVideo = state.activeCallHasVideo;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: hasVideo
                  ? RTCVideoView(
                      state.callService.remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : const _AudioCallSurface(),
            ),
            if (hasVideo)
              Positioned(
                right: 16,
                top: 16,
                width: 112,
                height: 160,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: RTCVideoView(
                      state.callService.localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Wrap(
                  spacing: 16,
                  children: [
                    IconButton.filledTonal(
                      tooltip: _micEnabled ? 'Mute' : 'Unmute',
                      onPressed: () {
                        setState(() => _micEnabled = !_micEnabled);
                        state.callService.toggleMicrophone(_micEnabled);
                      },
                      icon: Icon(_micEnabled ? Icons.mic : Icons.mic_off),
                    ),
                    if (hasVideo)
                      IconButton.filledTonal(
                        tooltip:
                            _cameraEnabled ? 'Camera off' : 'Camera on',
                        onPressed: () {
                          setState(() => _cameraEnabled = !_cameraEnabled);
                          state.callService.toggleCamera(_cameraEnabled);
                        },
                        icon: Icon(
                          _cameraEnabled
                              ? Icons.videocam
                              : Icons.videocam_off,
                        ),
                      ),
                    IconButton.filled(
                      tooltip: 'End call',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: state.endCall,
                      icon: const Icon(Icons.call_end),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioCallSurface extends StatelessWidget {
  const _AudioCallSurface();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: Colors.white24,
            child: Icon(Icons.call, color: Colors.white, size: 44),
          ),
          SizedBox(height: 20),
          Text(
            'Audio call',
            style: TextStyle(color: Colors.white, fontSize: 22),
          ),
        ],
      ),
    );
  }
}
