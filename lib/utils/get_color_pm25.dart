import 'package:flutter/material.dart';

class PmStatus {
  final String label;
  final Color color;

  const PmStatus(this.label, this.color);
}

PmStatus getPmStatus(int pm25) {
  if (pm25 < 0) {
    return const PmStatus('NULL', Colors.blue);
  } else if (pm25 <= 9) {
    return const PmStatus('BAIK', Color(0xFF00E400));
  } else if (pm25 <= 35) {
    return const PmStatus('SEDANG', Color.fromARGB(255, 240, 240, 10));
  } else if (pm25 <= 55) {
    return const PmStatus(
      'TIDAK SEHAT UNTUK KELOMPOK SENSITIF',
      Color(0xFFFF7E00),
    );
  } else if (pm25 <= 125) {
    return const PmStatus('TIDAK SEHAT', Color(0xFFFF0000));
  } else if (pm25 <= 225) {
    return const PmStatus('SANGAT TIDAK SEHAT', Color(0xFF8F3F97));
  } else {
    return const PmStatus('BERBAHAYA', Color(0xFF7E0023));
  }
}

Color getPmColor(int pm25) => getPmStatus(pm25).color;
