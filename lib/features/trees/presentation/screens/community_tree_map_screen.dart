import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/indonesian_date_formatter.dart';
import '../../../../core/widgets/tinted_info_box.dart';
import '../../application/tree_point_boundary.dart';
import '../controllers/tree_point_controller.dart';

/// Layar Peta Komunitas Pohon Guyub.
///
/// Menampilkan sebaran titik pohon penanaman resapan air di tingkat RT
/// menggunakan koordinat sel kasar (Geohash 7, ~153m x 153m) untuk menjaga
/// privasi warga. Dilengkapi OpenStreetMap attribution dan fallback daftar
/// jika perangkat dalam kondisi offline.
final class CommunityTreeMapScreen extends StatefulWidget {
  const CommunityTreeMapScreen({
    required this.controller,
    this.sessionToken,
    this.initialTrees,
    super.key,
  });

  final TreePointController controller;
  final String? sessionToken;
  final List<CommunityTreeItem>? initialTrees;

  @override
  State<CommunityTreeMapScreen> createState() => _CommunityTreeMapScreenState();
}

final class _CommunityTreeMapScreenState extends State<CommunityTreeMapScreen> {
  late Future<CommunityTreeMap> _mapFuture;
  int _viewMode = 0; // 0: Peta, 1: Daftar

  // Default coordinate: Jawa Timur / Tulungagung area (-8.06, 111.90)
  static const _fallbackCenter = LatLng(-8.0645, 111.9015);

  @override
  void initState() {
    super.initState();
    _loadTrees();
  }

  void _loadTrees() {
    if (widget.initialTrees != null) {
      _mapFuture = Future.value(
        CommunityTreeMap(
          items: widget.initialTrees!,
          totalVerifiedTrees: widget.initialTrees!.length,
        ),
      );
    } else {
      _mapFuture = widget.controller.loadCommunityMap(
        sessionToken: widget.sessionToken,
      );
    }
  }

  void _reload() {
    setState(() {
      _mapFuture = widget.controller.loadCommunityMap(
        sessionToken: widget.sessionToken,
      );
    });
  }

  LatLng _computeCenter(List<CommunityTreeItem> items) {
    if (items.isEmpty) return _fallbackCenter;
    final validPoints = items
        .where(
          (t) =>
              t.coarseLocation.approximateLat != 0.0 ||
              t.coarseLocation.approximateLng != 0.0,
        )
        .toList();
    if (validPoints.isEmpty) return _fallbackCenter;
    final avgLat =
        validPoints.fold<double>(
          0.0,
          (sum, t) => sum + t.coarseLocation.approximateLat,
        ) /
        validPoints.length;
    final avgLng =
        validPoints.fold<double>(
          0.0,
          (sum, t) => sum + t.coarseLocation.approximateLng,
        ) /
        validPoints.length;
    return LatLng(avgLat, avgLng);
  }

  void _showTreeDetails(CommunityTreeItem tree) {
    final colors = context.appColors;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.successBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.park_rounded,
                    color: colors.success,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tree.speciesHint ?? 'Pohon Resapan Guyub',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ditanam oleh ${tree.displaySubmitterName}',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.successBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colors.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: colors.success),
                      const SizedBox(width: 4),
                      Text(
                        'Terverifikasi RT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tanggal tanam: ${IndonesianDateFormatter.formatFull(tree.plantedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.shield_outlined, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Perkiraan area: Sel Geohash 7 (${tree.coarseLocation.cellId.isNotEmpty ? tree.coarseLocation.cellId : "~153m x 153m"}). Lokasi persis disamarkan.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
            if (tree.hasEvidencePhoto) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.photo_camera_outlined,
                      size: 16,
                      color: colors.primaryDark,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Foto bukti telah diverifikasi operator RT.',
                      style: TextStyle(fontSize: 12, color: colors.primaryDark),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peta Pohon Guyub RT'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<CommunityTreeMap>(
        future: _mapFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'Peta pohon belum dapat dimuat. Periksa koneksi dan coba lagi.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              ),
            );
          }

          final treeMap = snapshot.data;
          final trees = treeMap?.items ?? const <CommunityTreeItem>[];
          final mapCenter = _computeCenter(trees);

          return Column(
            children: [
              // Header ringkasan pohon
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.park, color: colors.success, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${trees.length} Pohon Resapan Terverifikasi',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    // Toggle Peta / Daftar
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          icon: Icon(Icons.map_outlined, size: 16),
                          label: Text('Peta'),
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: Icon(Icons.list_alt_outlined, size: 16),
                          label: Text('Daftar'),
                        ),
                      ],
                      selected: {_viewMode},
                      onSelectionChanged: (set) {
                        setState(() => _viewMode = set.first);
                      },
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),

              // Konten: Peta atau Daftar
              Expanded(
                child: _viewMode == 0
                    ? _buildMapView(trees, mapCenter, colors)
                    : _buildListView(trees, colors),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMapView(
    List<CommunityTreeItem> trees,
    LatLng center,
    AppColors colors,
  ) {
    if (trees.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.park_outlined, size: 48, color: colors.textSecondary),
              const SizedBox(height: 12),
              const Text(
                'Belum ada pohon terverifikasi di RT ini.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Warga yang menyelesaikan tugas penanaman pohon akan muncul di peta ini setelah diverifikasi RT.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          key: const Key('community-tree-flutter-map'),
          options: MapOptions(
            initialCenter: center,
            initialZoom: 15.0,
            minZoom: 10.0,
            maxZoom: 18.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'id.guyub.app',
            ),
            MarkerLayer(
              markers: [
                for (final tree in trees)
                  Marker(
                    key: Key('tree-marker-${tree.treePointId}'),
                    point: LatLng(
                      tree.coarseLocation.approximateLat,
                      tree.coarseLocation.approximateLng,
                    ),
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      onTap: () => _showTreeDetails(tree),
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.park,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SimpleAttributionWidget(
              source: Text('© OpenStreetMap contributors'),
              alignment: Alignment.bottomRight,
            ),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: TintedInfoBox(
            tint: TintType.info,
            icon: Icons.privacy_tip_outlined,
            child: const Text(
              'Titik pada peta adalah koordinat sel kasar Geohash 7 (~153m) '
              'untuk melindungi privasi rumah warga.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListView(List<CommunityTreeItem> trees, AppColors colors) {
    if (trees.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.park_outlined, size: 48, color: colors.textSecondary),
              const SizedBox(height: 12),
              const Text(
                'Belum ada pohon terverifikasi di RT ini.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Warga yang menyelesaikan tugas penanaman pohon akan muncul di daftar ini setelah diverifikasi RT.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: trees.length,
      itemBuilder: (context, index) {
        final tree = trees[index];
        return Card(
          key: Key('tree-list-item-${tree.treePointId}'),
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.border),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.successBg,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.park_rounded, color: colors.success, size: 22),
            ),
            title: Text(
              tree.speciesHint ?? 'Pohon Resapan Guyub',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Ditanam oleh ${tree.displaySubmitterName} • ${IndonesianDateFormatter.formatDateOnly(tree.plantedAt)}',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => _showTreeDetails(tree),
          ),
        );
      },
    );
  }
}
