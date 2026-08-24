import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// The "no active navigation yet" screen: a map list on the left (with
/// swipe-to-delete) and a "Start Navigation" panel on the right. Restyled
/// to the redesign's light/purple theme — this screen has no live map
/// canvas of its own (that only exists once navigation is active, still
/// rendered by `OccupancyGridViewer`), so it's safe to fully adopt the new
/// theme here without clashing with any sensor-visualization surface.
///
/// Every mutation (map selection, delete confirmation/removal, refresh,
/// start) is still reported back through the callbacks below exactly as
/// before — only the presentation changed in this pass.
class MapSelectionView extends StatelessWidget {
  final List<String> mapList;
  final String? selectedMap;
  final bool loadingMaps;

  /// Number of bookmarks associated with [map] — used only for the delete
  /// confirmation dialog's wording.
  final int Function(String map) bookmarksCountForMap;

  final VoidCallback onRefresh;
  final ValueChanged<String> onSelectMap;

  /// Called after the user confirms deletion of the map at [index] — the
  /// screen still owns removing it from its own list state and issuing the
  /// actual delete request (mirrors the original inline `onDismissed`).
  final void Function(String map, int index) onDeleteConfirmed;

  final VoidCallback onStartNavigation;

  const MapSelectionView({
    super.key,
    required this.mapList,
    required this.selectedMap,
    required this.loadingMaps,
    required this.bookmarksCountForMap,
    required this.onRefresh,
    required this.onSelectMap,
    required this.onDeleteConfirmed,
    required this.onStartNavigation,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.lightTheme,
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        final accent = theme.colorScheme.primary;

        return Container(
          color: AppColors.lightBackground,
          child: Row(
            children: [
              // Left side - Map List
              Container(
                width: 320,
                decoration: BoxDecoration(
                  color: AppColors.lightSurface,
                  border: Border(
                    right: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Available Maps',
                              style: theme.textTheme.titleLarge),
                          IconButton(
                            icon: Icon(Icons.refresh, color: accent),
                            onPressed: onRefresh,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Loading indicator or list
                    Expanded(
                      child: loadingMaps
                          ? Center(
                              child: CircularProgressIndicator(color: accent),
                            )
                          : mapList.isEmpty
                              ? Center(
                                  child: Text(
                                    'No maps available',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  itemCount: mapList.length,
                                  itemBuilder: (context, index) {
                                    final map = mapList[index];
                                    final isSelected = map == selectedMap;

                                    return Dismissible(
                                      key: Key(map),
                                      direction: DismissDirection.endToStart,
                                      confirmDismiss: (_) async {
                                        final bookmarksCount =
                                            bookmarksCountForMap(map);

                                        return await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text('Delete Map'),
                                                content: RichText(
                                                  text: TextSpan(
                                                    style: theme
                                                        .textTheme.bodyMedium,
                                                    children: [
                                                      TextSpan(
                                                        text:
                                                            'Are you sure you want to delete "$map"',
                                                      ),
                                                      if (bookmarksCount >
                                                          0) ...[
                                                        TextSpan(
                                                          text:
                                                              ' and its $bookmarksCount associated bookmarks',
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold),
                                                        ),
                                                      ],
                                                      const TextSpan(
                                                        text: '?',
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, false),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  TextButton(
                                                    style: TextButton.styleFrom(
                                                        foregroundColor: Colors
                                                            .red.shade400),
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, true),
                                                    child: const Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            ) ??
                                            false;
                                      },
                                      onDismissed: (_) =>
                                          onDeleteConfirmed(map, index),
                                      background: const SizedBox.shrink(),
                                      secondaryBackground: Container(
                                        alignment: Alignment.centerRight,
                                        padding:
                                            const EdgeInsets.only(right: 20),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade400,
                                          borderRadius: BorderRadius.circular(
                                              AppSpacing.radiusLg),
                                        ),
                                        child: const Icon(
                                          Icons.delete_forever,
                                          color: Colors.white,
                                        ),
                                      ),
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? accent.withValues(alpha: 0.08)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                              AppSpacing.radiusLg),
                                          border: Border.all(
                                            color: isSelected
                                                ? accent
                                                : Colors.transparent,
                                            width: 1,
                                          ),
                                        ),
                                        child: ListTile(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                AppSpacing.radiusLg),
                                          ),
                                          leading: Icon(
                                            Icons.map_outlined,
                                            color: isSelected
                                                ? accent
                                                : theme.colorScheme
                                                    .onSurfaceVariant,
                                          ),
                                          title: Text(
                                            map,
                                            style: theme.textTheme.bodyLarge
                                                ?.copyWith(
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          onTap: () => onSelectMap(map),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),

              // Right side - Controls
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Icon and title
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.route_outlined,
                          size: 64,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text('Navigation Mode',
                          style: theme.textTheme.headlineSmall),
                      const SizedBox(height: AppSpacing.sm),

                      // Selected map display
                      Text(
                        selectedMap != null
                            ? 'Selected: $selectedMap'
                            : 'No map selected',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Start button - Primary action
                      FilledButton.icon(
                        onPressed: mapList.isEmpty || selectedMap == null
                            ? null
                            : onStartNavigation,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start Navigation'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xl,
                              vertical: AppSpacing.md),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
