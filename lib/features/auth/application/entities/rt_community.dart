/// Konteks komunitas RT/RW yang menjadi batas kepemilikan (ownership boundary)
/// data kesiapsiagaan pada Guyub.id.
///
/// Riwayat kesiapsiagaan melekat pada entitas RT ini, bukan pada akun operator
/// individu (PRD INV-10), sehingga pergantian pengurus tidak menghapus riwayat.
///
/// **Data minimal (INV-06):** entitas ini tidak boleh menyimpan GPS presisi,
/// NIK, atau alamat lengkap rumah tangga mana pun.
final class RtCommunity {
  /// Identitas unik komunitas RT pada backend.
  final String id;

  /// Nama kelurahan (konteks wilayah indikatif, bukan alamat rumah).
  final String kelurahanName;

  /// Label RT, misalnya `RT 05`.
  final String rtLabel;

  /// Label RW, misalnya `RW 03`.
  final String rwLabel;

  /// Nama tampilan komunitas yang aman dipublikasikan ke warganya.
  final String displayName;

  const RtCommunity({
    required this.id,
    required this.kelurahanName,
    required this.rtLabel,
    required this.rwLabel,
    required this.displayName,
  });

  /// Label ringkas komunitas, misalnya `RT 05 / RW 03`.
  String get shortLabel => '$rtLabel / $rwLabel';

  @override
  String toString() => 'RtCommunity($id)';
}