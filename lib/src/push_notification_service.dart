import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    return;
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  static const _messagesChannel = AndroidNotificationChannel(
    'messages',
    'Messages',
    description: 'New chat messages',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  final _localNotifications = FlutterLocalNotificationsPlugin();
  final _deviceInfo = DeviceInfoPlugin();
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _initialized = false;
  bool _firebaseAvailable = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
      _firebaseAvailable = true;
    } catch (_) {
      _firebaseAvailable = false;
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: true,
    );

    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_messagesChannel);

    FirebaseMessaging.onMessage.listen(_showForegroundMessage);
  }

  Future<void> registerDevice(ApiClient api) async {
    await initialize();
    if (!_firebaseAvailable) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    await api.registerPushToken(
      token: token,
      platform: _platform,
      deviceId: await _deviceId(),
    );

    _tokenRefreshSubscription ??=
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      unawaited(
        api.registerPushToken(
          token: newToken,
          platform: _platform,
          deviceId: null,
        ),
      );
    });
  }

  Future<void> unregisterDevice(ApiClient api, String accessToken) async {
    await initialize();
    if (!_firebaseAvailable) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    await api.unregisterPushToken(token, accessTokenOverride: accessToken);
  }

  Future<void> _showForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    if (data['type'] != 'chat_message') return;

    final chatId = data['chatId'] ?? message.messageId ?? 'messages';
    final title = data['senderName'] ??
        message.notification?.title ??
        'New message';
    final body = data['body'] ??
        message.notification?.body ??
        'Open Chat Call to read it';
    final unreadCount = int.tryParse(data['chatUnreadCount'] ?? '') ?? 1;

    await _localNotifications.show(
      id: _stableNotificationId(chatId),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _messagesChannel.id,
          _messagesChannel.name,
          channelDescription: _messagesChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          tag: 'chat:$chatId',
          groupKey: 'chat:$chatId',
          number: unreadCount,
          channelShowBadge: true,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: chatId,
    );
  }

  int _stableNotificationId(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  Future<String?> _deviceId() async {
    if (Platform.isAndroid) {
      return (await _deviceInfo.androidInfo).id;
    }
    if (Platform.isIOS) {
      return (await _deviceInfo.iosInfo).identifierForVendor;
    }
    return null;
  }

  String get _platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'web';
  }
}
