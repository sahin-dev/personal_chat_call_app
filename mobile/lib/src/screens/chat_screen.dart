import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../widgets/user_avatar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  PlatformFile? _attachment;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final other = _otherParticipant(state);
    final online = state.isUserOnline(other?.id);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        title: Row(
          children: [
            UserAvatar(user: other, online: online, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    other?.name ?? 'Chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    online ? 'Online' : 'Offline',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: online
                              ? Colors.green.shade700
                              : Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Audio call',
            onPressed: other == null
                ? null
                : () => state.startCall(other, video: false),
            icon: const Icon(Icons.call),
          ),
          IconButton(
            tooltip: 'Video call',
            onPressed: other == null
                ? null
                : () => state.startCall(other, video: true),
            icon: const Icon(Icons.videocam),
          ),
        ],
      ),
      body: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Column(
          children: [
            Expanded(
              child: state.activeMessages.isEmpty
                  ? const _EmptyConversation()
                  : GestureDetector(
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                        itemCount: state.activeMessages.length,
                        itemBuilder: (context, index) {
                          final messageIndex =
                              state.activeMessages.length - 1 - index;
                          final message = state.activeMessages[messageIndex];
                          final mine =
                              message.senderId == state.currentUser?.id;
                          final showDate = messageIndex == 0 ||
                              !_sameDay(
                                state
                                    .activeMessages[messageIndex - 1].createdAt,
                                message.createdAt,
                              );
                          return Column(
                            children: [
                              if (showDate)
                                _DateSeparator(date: message.createdAt),
                              _MessageBubble(message: message, mine: mine),
                            ],
                          );
                        },
                      ),
                    ),
            ),
            Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 1,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _attachment == null
                            ? const SizedBox.shrink()
                            : _AttachmentPreview(
                                key: ValueKey(_attachment!.path),
                                file: _attachment!,
                                onRemove: () =>
                                    setState(() => _attachment = null),
                              ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton.filledTonal(
                            tooltip: 'Attach file',
                            onPressed: _pickFile,
                            style: IconButton.styleFrom(
                              fixedSize: const Size.square(44),
                            ),
                            icon: const Icon(Icons.attach_file),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              minLines: 1,
                              maxLines: 4,
                              decoration: InputDecoration(
                                hintText: _attachment == null
                                    ? 'Message'
                                    : 'Add a caption',
                                filled: true,
                                fillColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                border: const OutlineInputBorder(
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            tooltip: 'Send',
                            onPressed: _send,
                            style: IconButton.styleFrom(
                              fixedSize: const Size.square(44),
                            ),
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _send() {
    final text = _messageController.text;
    final attachment = _attachment;
    if (attachment == null) {
      context.read<AppState>().sendText(text);
      _messageController.clear();
      return;
    }

    final path = attachment.path;
    if (path == null) return;
    setState(() {
      _attachment = null;
      _messageController.clear();
    });
    unawaited(
      context.read<AppState>().sendFile(File(path), caption: text),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    final file = result?.files.single;
    if (file?.path == null || !mounted) return;
    setState(() => _attachment = file);
  }

  AppUser? _otherParticipant(AppState state) {
    for (final user in state.activeChat?.participants ?? <AppUser>[]) {
      if (user.id != state.currentUser?.id) {
        return user;
      }
    }
    return null;
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 42,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'Start the conversation',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    super.key,
    required this.file,
    required this.onRemove,
  });

  final PlatformFile file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final path = file.path;
    final isImage = _isImageName(file.name);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox.square(
                  dimension: 48,
                  child: isImage && path != null
                      ? Image.file(File(path), fit: BoxFit.cover)
                      : ColoredBox(
                          color: Theme.of(context).colorScheme.surface,
                          child: const Icon(Icons.insert_drive_file),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatFileSize(file.size),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove attachment',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Text(
            _formatMessageDate(date),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = mine ? colors.primaryContainer : colors.surface;
    final maxWidth = (MediaQuery.sizeOf(context).width * 0.78)
        .clamp(220.0, 340.0)
        .toDouble();

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          top: 2,
          bottom: 2,
          left: mine ? 40 : 0,
          right: mine ? 0 : 40,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Material(
            color: color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: mine
                  ? BorderSide.none
                  : BorderSide(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onLongPress:
                  mine && !message.isDeleted && message.localStatus == null
                      ? () => _delete(context)
                      : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _content(context),
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatMessageTime(message.createdAt),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                          ),
                          if (mine) ...[
                            const SizedBox(width: 4),
                            _MessageStatusIndicator(
                              status: message.recipientStatus,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (message.isDeleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.block,
            size: 15,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            'Message deleted',
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    if (message.type == MessageKind.text) {
      return Text(
        message.text ?? '',
        style: const TextStyle(height: 1.28),
      );
    }

    final file = message.file;
    if (file == null) return const Text('File unavailable');
    final caption = message.text?.trim();
    final isImage =
        file.mimeType.startsWith('image/') || _isImageName(file.originalName);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isImage)
          GestureDetector(
            onTap: () => _showImage(context, file),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 224),
                child: AspectRatio(
                  aspectRatio: 224 / 154,
                  child: file.localPath == null
                      ? Image.network(
                          AppConfig.resolveFileUrl(file.url),
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                                  ? child
                                  : const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Colors.black12,
                            child: Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        )
                      : Image.file(File(file.localPath!), fit: BoxFit.cover),
                ),
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SizedBox.square(
                    dimension: 40,
                    child: Icon(
                      _fileIcon(file.mimeType),
                      size: 21,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.originalName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatFileSize(file.size),
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (caption?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text(caption!, style: const TextStyle(height: 1.28)),
        ],
        if (message.uploadProgress != null &&
            (message.localStatus == MessageReceiptStatus.sending ||
                message.localStatus == MessageReceiptStatus.failed)) ...[
          const SizedBox(height: 10),
          _FileUploadProgress(
            progress: message.uploadProgress!,
            failed: message.localStatus == MessageReceiptStatus.failed,
          ),
        ],
      ],
    );
  }

  void _showImage(BuildContext context, SharedFile file) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          height: MediaQuery.sizeOf(context).height * 0.8,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  child: Center(
                    child: file.localPath == null
                        ? Image.network(
                            AppConfig.resolveFileUrl(file.url),
                            fit: BoxFit.contain,
                          )
                        : Image.file(File(file.localPath!),
                            fit: BoxFit.contain),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton.filledTonal(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _delete(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListTile(
          leading: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            'Delete message',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          onTap: () {
            Navigator.of(sheetContext).pop();
            context.read<AppState>().deleteMessage(message.id);
          },
        ),
      ),
    );
  }
}

class _FileUploadProgress extends StatelessWidget {
  const _FileUploadProgress({required this.progress, required this.failed});

  final double progress;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final percentage = (progress * 100).round();
    final color = failed ? colors.error : colors.primary;
    final label = failed
        ? 'Upload failed'
        : progress >= 1
            ? 'Upload complete'
            : 'Uploading';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                failed ? Icons.error_outline_rounded : Icons.upload_rounded,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Text(
                '$percentage%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              color: color,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageStatusIndicator extends StatelessWidget {
  const _MessageStatusIndicator({required this.status});

  final MessageReceiptStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (status) {
      MessageReceiptStatus.sending => (
          'Sending',
          Icons.schedule_rounded,
          Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      MessageReceiptStatus.sent => (
          'Sent',
          Icons.done_rounded,
          Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      MessageReceiptStatus.delivered => (
          'Delivered',
          Icons.done_all_rounded,
          Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      MessageReceiptStatus.seen => (
          'Seen',
          Icons.done_all_rounded,
          Theme.of(context).colorScheme.primary,
        ),
      MessageReceiptStatus.failed => (
          'Failed to send',
          Icons.error_outline_rounded,
          Theme.of(context).colorScheme.error,
        ),
    };

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Icon(
          icon,
          size: 15,
          color: color,
        ),
      ),
    );
  }
}

bool _isImageName(String name) {
  final extension = name.toLowerCase().split('.').last;
  return const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'}
      .contains(extension);
}

String _formatMessageTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
}

bool _sameDay(DateTime first, DateTime second) {
  final a = first.toLocal();
  final b = second.toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _formatMessageDate(DateTime dateTime) {
  final date = dateTime.toLocal();
  final now = DateTime.now();
  if (_sameDay(date, now)) return 'Today';
  final yesterday = now.subtract(const Duration(days: 1));
  if (_sameDay(date, yesterday)) return 'Yesterday';
  return '${date.day}/${date.month}/${date.year}';
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

IconData _fileIcon(String mimeType) {
  if (mimeType.contains('pdf')) return Icons.picture_as_pdf_outlined;
  if (mimeType.startsWith('audio/')) return Icons.audio_file_outlined;
  if (mimeType.startsWith('video/')) return Icons.video_file_outlined;
  return Icons.insert_drive_file_outlined;
}
