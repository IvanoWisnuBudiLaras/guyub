/// Data kontak darurat nasional resmi Republik Indonesia.
///
/// Digunakan pada kondisi tanpa sesi dan tanpa data direktori tersimpan di perangkat.
/// Semua nomor telah diverifikasi dari situs web kementerian/lembaga resmi.
final class NationalEmergencyContact {
  const NationalEmergencyContact({
    required this.label,
    required this.number,
    required this.description,
    required this.sourceAuthority,
    required this.sourceUrl,
    required this.verificationDate,
  });

  final String label;
  final String number;
  final String description;
  final String sourceAuthority;
  final String sourceUrl;
  final String verificationDate;
}

/// Daftar nomor darurat nasional resmi terverifikasi per 17 Oktober 2026.
const List<NationalEmergencyContact> kNationalEmergencyContacts = [
  NationalEmergencyContact(
    label: 'Panggilan Darurat Terpadu',
    number: '112',
    description: 'Layanan nomor tunggal panggilan darurat (bebas pulsa) terintegrasi BPBD, Damkar, Medis, dan Kepolisian.',
    sourceAuthority:
        'Kementerian Komunikasi dan Digital RI (Permenkominfo No. 10/2016)',
    sourceUrl: 'https://layanan112.komdigi.go.id',
    verificationDate: '2026-10-17',
  ),
  NationalEmergencyContact(
    label: 'Kepolisian RI',
    number: '110',
    description: 'Layanan kontak darurat 24 jam untuk laporan kriminalitas, ketertiban, dan bahaya keamanan.',
    sourceAuthority: 'Kepolisian Negara Republik Indonesia (Polri)',
    sourceUrl: 'https://polri.go.id',
    verificationDate: '2026-10-17',
  ),
  NationalEmergencyContact(
    label: 'Pemadam Kebakaran & Penyelamatan',
    number: '113',
    description: 'Layanan darurat kebakaran dan operasi evakuasi penyelamatan non-kebakaran.',
    sourceAuthority:
        'Ditjen Bina Administrasi Kewilayahan Kementerian Dalam Negeri RI',
    sourceUrl: 'https://ditjenbinaadwil.kemendagri.go.id',
    verificationDate: '2026-10-17',
  ),
  NationalEmergencyContact(
    label: 'Layanan Medis Darurat (SPGDT)',
    number: '119',
    description: 'National Command Center (NCC) kegawatdaruratan medis dan rujukan ambulans terpadu.',
    sourceAuthority: 'Kementerian Kesehatan RI (Permenkes No. 19/2016)',
    sourceUrl: 'https://kemkes.go.id',
    verificationDate: '2026-10-17',
  ),
  NationalEmergencyContact(
    label: 'Basarnas (Pencarian & Pertolongan)',
    number: '115',
    description: 'Siaga pencarian dan pertolongan korban bencana, musibah, dan kondisi membahayakan jiwa.',
    sourceAuthority: 'Badan Nasional Pencarian dan Pertolongan (Basarnas RI)',
    sourceUrl: 'https://basarnas.go.id',
    verificationDate: '2026-10-17',
  ),
];
