import 'package:flutter/material.dart';

class TvocStatus {
  final String label;
  final Color color;

  const TvocStatus(this.label, this.color);
}

TvocStatus getTvocStatus(double tvoc) {
  if (tvoc < 0) {
    return const TvocStatus('NULL', Colors.blue);
  } else if (tvoc < 67) {
    return const TvocStatus('SANGAT BAIK', Color(0xFF00E400));
  } else if (tvoc <= 222) {
    return const TvocStatus('BAIK', Color(0xFF90EE90));
  } else if (tvoc <= 665) {
    return const TvocStatus('SEDANG', Color(0xFFFFFF00));
  } else if (tvoc <= 2218) {
    return const TvocStatus('KURANG BAIK', Color(0xFFFF7E00));
  } else {
    return const TvocStatus('TIDAK BAIK', Color(0xFFFF0000));
  }
}

Color getTvocColor(double tvoc) => getTvocStatus(tvoc).color;
