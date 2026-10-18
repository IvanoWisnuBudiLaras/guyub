import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/alert_banner.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/tinted_info_box.dart';
import '../../../auth/application/resident_session.dart';
import '../../application/tree_point_boundary.dart';
import '../../domain/tree_point.dart';
import '../controllers/tree_point_controller.dart';
import '../widgets/tree_privacy_rationale_sheet.dart';

typedef PickCameraImage = Future<Uint8List?> Function();

/// Layar in-app camera dan pengajuan titik penanaman pohon warga.
final class TreeCaptureScreen extends StatefulWidget {
  const TreeCaptureScreen({
    required this.session,
    required this.taskId,
    required this.taskTitle,
    required this.controller,
    this.pickCameraImage,
    super.key,
  });

  final ResidentSession session;
  final String taskId;
  final String taskTitle;
  final TreePointController controller;
  final PickCameraImage? pickCameraImage;

  @override
  State<TreeCaptureScreen> createState() => _TreeCaptureScreenState();
}

final class _TreeCaptureScreenState extends State<TreeCaptureScreen> {
  final TextEditingController _speciesController = TextEditingController();

  DeviceGpsReading? _gpsReading;
  bool _readingGps = false;
  String? _gpsError;

  Uint8List? _capturedImageBytes;
  bool _submitting = false;
  String? _submitError;
  TreePointSubmissionResult? _submissionResult;
  bool _privacyAcknowledged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPrivacyAndGps();
    });
  }

  @override
  void dispose() {
    _speciesController.dispose();
    super.dispose();
  }

  Future<void> _initPrivacyAndGps() async {
    final agreed = await TreePrivacyRationaleSheet.show(context);
    if (!mounted) return;
    if (agreed != true) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _privacyAcknowledged = true);
    await _refreshGps();
  }

  Future<void> _refreshGps() async {
    setState(() {
      _readingGps = true;
      _gpsError = null;
    });

    try {
      final reading = await widget.controller.getCurrentGpsReading();
      if (!mounted) return;
      setState(() {
        _gpsReading = reading;
        _readingGps = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gpsError = e.toString();
        _readingGps = false;
      });
    }
  }

  Future<void> _takePhoto() async {
    try {
      final picker = widget.pickCameraImage ?? _defaultCameraPicker;
      final bytes = await picker();
      if (bytes != null && mounted) {
        setState(() {
          _capturedImageBytes = bytes;
          _submitError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitError = 'Gagal mengakses kamera: $e');
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      final bytes = await file?.readAsBytes();
      if (bytes != null && mounted) {
        setState(() {
          _capturedImageBytes = bytes;
          _submitError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitError = 'Gagal mengakses galeri: $e');
      }
    }
  }

  Future<Uint8List?> _defaultCameraPicker() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      return await file?.readAsBytes();
    } catch (_) {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      return await file?.readAsBytes();
    }
  }

  Future<void> _submit() async {
    final reading = _gpsReading;
    if (reading == null || !reading.isValid) {
      setState(
        () =>
            _submitError = 'Lokasi GPS belum memenuhi syarat (akurasi ≤ 30m).',
      );
      return;
    }

    if (_capturedImageBytes == null) {
      setState(
        () => _submitError =
            'Foto pohon wajib diambil langsung menggunakan kamera.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final result = await widget.controller.submitTreePoint(
        taskId: widget.taskId,
        speciesHint: _speciesController.text,
        reading: reading,
        rawImageBytes: _capturedImageBytes,
      );

      if (mounted) {
        setState(() {
          _submissionResult = result;
          _submitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitError = e.toString();
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Tanam & Dokumentasikan Pohon')),
      body: !_privacyAcknowledged
          ? const SizedBox.shrink()
          : _submissionResult != null
          ? _buildSuccessView(context)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sub-header konteks RT
                  Text(
                    'Tugas: ${widget.taskTitle}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 1. Kartu Status GPS Akurat
                  _buildGpsStatusCard(context),
                  const SizedBox(height: 12),

                  // 2. Kartu In-App Camera
                  _buildCameraCard(context),
                  const SizedBox(height: 12),

                  // 3. Kartu Jenis Pohon
                  _buildSpeciesCard(context),
                  const SizedBox(height: 12),

                  // 4. Panduan Keselamatan Terkunci
                  _buildSafetyCard(context),
                  const SizedBox(height: 16),

                  // Error Banner
                  if (_submitError != null) ...[
                    AlertBanner.danger(
                      title: 'Gagal Mengajukan Titik Pohon',
                      message: _submitError!,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Tombol Submit
                  FilledButton.icon(
                    key: const Key('tree-submit-button'),
                    onPressed:
                        _submitting ||
                            _capturedImageBytes == null ||
                            _gpsReading == null ||
                            !_gpsReading!.isValid
                        ? null
                        : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(
                      _submitting
                          ? 'Mengirim Data Pohon...'
                          : 'Ajukan Titik Pohon ke RT',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildGpsStatusCard(BuildContext context) {
    final colors = context.appColors;
    final reading = _gpsReading;

    if (_readingGps) {
      return SectionCard(
        title: 'Status Sensor GPS',
        icon: Icons.gps_not_fixed,
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Membaca sinyal satelit GPS perangkat...'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_gpsError != null || reading == null) {
      return SectionCard(
        title: 'Status Sensor GPS',
        icon: Icons.gps_off,
        children: [
          TintedInfoBox.warning(
            title: 'Sinyal GPS Belum Tersedia',
            text:
                _gpsError ??
                'Tidak dapat membaca lokasi GPS. Pastikan izin lokasi aktif.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('tree-retry-gps-button'),
            onPressed: _refreshGps,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba Lagi Sensor GPS'),
          ),
        ],
      );
    }

    // Evaluasi akurasi & mock status
    final isMock = reading.isMocked;
    final isAccurate = reading.isAcceptableAccuracy;

    final badgeColor = isMock
        ? colors.dangerBg
        : isAccurate
        ? colors.successBg
        : colors.warningBg;

    final textColor = isMock
        ? colors.danger
        : isAccurate
        ? colors.success
        : colors.warning;

    final icon = isMock
        ? Icons.warning_amber_outlined
        : isAccurate
        ? Icons.check_circle_outline
        : Icons.info_outline;

    final statusText = isMock
        ? 'Lokasi Palsu (Mock Location) Terdeteksi!'
        : isAccurate
        ? 'GPS Siap & Akurat (±${reading.accuracyMeters.toStringAsFixed(1)} m)'
        : 'Sinyal Kurang Kuat: ±${reading.accuracyMeters.toStringAsFixed(1)} m (Wajib ≤ 30 m)';

    return SectionCard(
      title: 'Status Sensor GPS',
      icon: Icons.my_location,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: textColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: textColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              IconButton(
                key: const Key('tree-refresh-gps-icon'),
                tooltip: 'Perbarui GPS',
                icon: Icon(Icons.refresh, size: 18, color: textColor),
                onPressed: _refreshGps,
              ),
            ],
          ),
        ),
        if (!isAccurate && !isMock) ...[
          const SizedBox(height: 8),
          Text(
            'Tips: Berpindahlah ke luar ruangan/ruang terbuka beberapa meter agar penerimaan GPS lebih optimal.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _buildCameraCard(BuildContext context) {
    final bytes = _capturedImageBytes;

    return SectionCard(
      title: 'Foto Pohon Langsung (Kamera)',
      icon: Icons.photo_camera_outlined,
      children: [
        if (bytes == null) ...[
          OutlinedButton.icon(
            key: const Key('tree-capture-camera-button'),
            onPressed: _submitting ? null : _takePhoto,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Buka Kamera In-App'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('tree-pick-gallery-button'),
            onPressed: _submitting ? null : _pickFromGallery,
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Atau pilih foto dari galeri'),
          ),
        ]
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              bytes,
              key: const Key('tree-captured-preview'),
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                size: 16,
                color: Colors.green,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Foto tersimpan (EXIF dibuang otomatis)',
                  style: TextStyle(fontSize: 12, color: Colors.green),
                ),
              ),
              TextButton.icon(
                key: const Key('tree-retake-photo-button'),
                onPressed: _submitting ? null : _takePhoto,
                icon: const Icon(Icons.replay, size: 16),
                label: const Text('Foto Ulang'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSpeciesCard(BuildContext context) {
    return SectionCard(
      title: 'Jenis Pohon (Opsional)',
      icon: Icons.eco_outlined,
      children: [
        TextField(
          key: const Key('tree-species-input'),
          controller: _speciesController,
          maxLength: 60,
          decoration: const InputDecoration(
            hintText: 'Contoh: Mangga Arumanis, Ketapang Kencana',
            helperText:
                'Dilarang memasukkan NIK, nomor telepon, atau alamat rumah',
            helperMaxLines: 2,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }

  Widget _buildSafetyCard(BuildContext context) {
    return TintedInfoBox(
      tint: TintType.warning,
      icon: Icons.health_and_safety_outlined,
      title: 'Instruksi Keselamatan Terkunci:',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SizedBox(height: 4),
          Text(
            '• Pastikan lokasi tanam aman dari pipa bawah tanah dan kabel listrik.',
          ),
          SizedBox(height: 4),
          Text('• Dilarang menanam di lereng/tebing curam yang rawan longsor.'),
          SizedBox(height: 4),
          Text(
            '• Gunakan sarung tangan pelindung dan peralatan tanam dengan aman.',
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(BuildContext context) {
    final result = _submissionResult!;
    final colors = context.appColors;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.successBg,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.task_alt, size: 64, color: colors.success),
            ),
            const SizedBox(height: 20),
            Text(
              'Titik Pohon Berhasil Diajukan!',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Pengajuan titik pohon Anda telah tercatat dan sedang menunggu verifikasi dari Pengurus RT.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Info ringkasan sel
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Status:'),
                      Text(
                        result.status.indonesianLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colors.warning,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sel Wilayah Kasar:'),
                      Text(
                        result.coarseLocation.cellId,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            FilledButton(
              key: const Key('tree-success-back-button'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Kembali ke Halaman Tugas'),
            ),
          ],
        ),
      ),
    );
  }
}
