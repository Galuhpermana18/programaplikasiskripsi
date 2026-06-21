import 'package:flutter/material.dart';

class PmStatus {
  final String label;
  final Color color;

  PmStatus(this.label, this.color);
}

PmStatus getPmStatus(int pm25) {
  if (pm25 == 0) {
    return PmStatus('NULL', Colors.blue);
  }

  if (pm25 <= 50) {
    return PmStatus('BAIK', const Color.fromARGB(255, 0, 228, 0));
  } else if (pm25 <= 100) {
    return PmStatus('SEDANG', const Color.fromARGB(255, 190, 190, 5));
  } else if (pm25 <= 150) {
    return PmStatus(
      'TIDAK SEHAT BAGI SENSITIF',
      const Color.fromARGB(255, 255, 126, 0),
    );
  } else if (pm25 <= 200) {
    return PmStatus('TIDAK SEHAT', const Color.fromARGB(255, 255, 0, 0));
  } else if (pm25 <= 300) {
    return PmStatus(
      'SANGAT TIDAK SEHAT',
      const Color.fromARGB(255, 143, 63, 151),
    );
  } else {
    return PmStatus('BERBAHAYA', const Color.fromARGB(255, 126, 0, 35));
  }
}

Color getPmColor(int pm25) {
  if (pm25 <= 50) {
    return const Color.fromARGB(255, 196, 225, 243);
  } else if (pm25 <= 100) {
    return const Color.fromARGB(255, 218, 218, 104);
  } else if (pm25 <= 150) {
    return const Color.fromARGB(255, 231, 139, 46);
  } else if (pm25 <= 200) {
    return const Color.fromARGB(255, 236, 98, 98);
  } else if (pm25 <= 300) {
    return const Color.fromARGB(255, 143, 63, 151);
  } else {
    return const Color.fromARGB(255, 126, 71, 87);
  }
}
