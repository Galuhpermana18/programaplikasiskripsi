import 'package:flutter/material.dart';

class Pm10Status {
  final String label;
  final Color color;

  const Pm10Status(this.label, this.color);
}

Pm10Status getPm10Status(int pm10) {
  if (pm10 < 0) {
    return const Pm10Status('NULL', Colors.blue);
  } else if (pm10 <= 50) {
    return const Pm10Status('BAIK', Color(0xFF00E400));
  } else if (pm10 <= 150) {
    return const Pm10Status('SEDANG', Color(0xFFFFFF00));
  } else if (pm10 <= 350) {
    return const Pm10Status('TIDAK SEHAT', Color(0xFFFF0000));
  } else if (pm10 <= 420) {
    return const Pm10Status('SANGAT TIDAK SEHAT', Color(0xFF8F3F97));
  } else {
    return const Pm10Status('BERBAHAYA', Color(0xFF7E0023));
  }
}

Color getPm10Color(int pm10) => getPm10Status(pm10).color;
