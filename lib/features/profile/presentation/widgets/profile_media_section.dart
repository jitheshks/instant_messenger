import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:instant_messenger/app/theme/app_colors.dart';
import 'package:instant_messenger/features/messaging/domain/models/chat_message.dart';
import 'package:instant_messenger/features/profile/domain/services/profile_media_service.dart';
import 'package:instant_messenger/shared/utils/date_formatter.dart';

/// Reusable section card displaying shared media, links, and documents with horizontal preview.
class ProfileMediaSection extends StatelessWidget {
  final ProfileMediaSummary mediaSummary;

  const ProfileMediaSection({
    super.key,
    required this.mediaSummary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final containerColor = isDark
        ? AppColors.darkSurfaceContainer
        : AppColors.lightSurface;
    final primaryTextColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _openFullGallery(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Media, links, and docs',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                        ),
                      ),
                    ),
                    Text(
                      '${mediaSummary.totalCount}',
                      style: TextStyle(
                        fontSize: 14,
                        color: secondaryTextColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: secondaryTextColor,
                    ),
                  ],
                ),
              ),
            ),

            if (mediaSummary.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  'No media, links, or documents shared yet',
                  style: TextStyle(fontSize: 14, color: secondaryTextColor),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  height: 76,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: mediaSummary.mediaMessages.isNotEmpty
                        ? mediaSummary.mediaMessages.length
                        : (mediaSummary.documentMessages.isNotEmpty
                            ? mediaSummary.documentMessages.length
                            : mediaSummary.linkMessages.length),
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      if (mediaSummary.mediaMessages.isNotEmpty) {
                        final msg = mediaSummary.mediaMessages[index];
                        return _buildMediaThumbnail(context, msg);
                      } else if (mediaSummary.documentMessages.isNotEmpty) {
                        final msg = mediaSummary.documentMessages[index];
                        return _buildDocThumbnail(context, msg);
                      } else {
                        final msg = mediaSummary.linkMessages[index];
                        return _buildLinkThumbnail(context, msg);
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaThumbnail(BuildContext context, ChatMessage msg) {
    final media = msg.media;
    final thumb = media?.thumbUrl ?? media?.url;
    final isVideo = media?.kind == MediaKind.video;

    return GestureDetector(
      onTap: () => _openFullGallery(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 76,
          height: 76,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumb != null && thumb.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: thumb,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const Center(
                    child: Icon(Icons.image_outlined, size: 24, color: Colors.grey),
                  ),
                  errorWidget: (_, _, _) => const Icon(Icons.broken_image, size: 28),
                )
              else
                Icon(isVideo ? Icons.videocam : Icons.photo, size: 28),
              if (isVideo)
                Container(
                  color: Colors.black26,
                  child: const Center(
                    child: Icon(Icons.play_circle_fill, color: Colors.white, size: 28),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocThumbnail(BuildContext context, ChatMessage msg) {
    final fileName = msg.media?.fileName ?? 'Document';
    return GestureDetector(
      onTap: () => _openFullGallery(context),
      child: Container(
        width: 76,
        height: 76,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.description, size: 28, color: AppColors.brandPrimary),
            const SizedBox(height: 4),
            Text(
              fileName,
              style: const TextStyle(fontSize: 9),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkThumbnail(BuildContext context, ChatMessage msg) {
    final url = ProfileMediaService.extractFirstUrl(msg.text) ?? '';
    return GestureDetector(
      onTap: () => _openFullGallery(context),
      child: Container(
        width: 76,
        height: 76,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.link, size: 28, color: Colors.blueAccent),
            const SizedBox(height: 4),
            Text(
              url,
              style: const TextStyle(fontSize: 9),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _openFullGallery(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _FullMediaGallerySheet(mediaSummary: mediaSummary),
    );
  }
}

class _FullMediaGallerySheet extends StatelessWidget {
  final ProfileMediaSummary mediaSummary;

  const _FullMediaGallerySheet({required this.mediaSummary});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Media, links, and docs'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Media (${mediaSummary.mediaMessages.length})'),
              Tab(text: 'Docs (${mediaSummary.documentMessages.length})'),
              Tab(text: 'Links (${mediaSummary.linkMessages.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Media Grid
            mediaSummary.mediaMessages.isEmpty
                ? const Center(child: Text('No media shared'))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: mediaSummary.mediaMessages.length,
                    itemBuilder: (context, i) {
                      final m = mediaSummary.mediaMessages[i].media;
                      final url = m?.thumbUrl ?? m?.url ?? '';
                      return CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: Colors.grey[300]),
                        errorWidget: (_, _, _) => const Icon(Icons.broken_image),
                      );
                    },
                  ),

            // Docs List
            mediaSummary.documentMessages.isEmpty
                ? const Center(child: Text('No documents shared'))
                : ListView.builder(
                    itemCount: mediaSummary.documentMessages.length,
                    itemBuilder: (context, i) {
                      final msg = mediaSummary.documentMessages[i];
                      final name = msg.media?.fileName ?? 'Document';
                      final sizeBytes = msg.media?.size ?? 0;
                      final sizeMb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
                      return ListTile(
                        leading: const Icon(Icons.insert_drive_file, color: AppColors.brandPrimary),
                        title: Text(name),
                        subtitle: Text('$sizeMb MB • ${DateFormatter.formatCallDateTime(msg.sentAt)}'),
                      );
                    },
                  ),

            // Links List
            mediaSummary.linkMessages.isEmpty
                ? const Center(child: Text('No links shared'))
                : ListView.builder(
                    itemCount: mediaSummary.linkMessages.length,
                    itemBuilder: (context, i) {
                      final msg = mediaSummary.linkMessages[i];
                      final url = ProfileMediaService.extractFirstUrl(msg.text) ?? '';
                      return ListTile(
                        leading: const Icon(Icons.link, color: Colors.blueAccent),
                        title: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(DateFormatter.formatCallDateTime(msg.sentAt)),
                        trailing: const Icon(Icons.copy, size: 18),
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: url));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Link copied to clipboard')),
                            );
                          }
                        },
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
