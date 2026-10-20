String formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String formatDurationMs(int durationMs) {
  return formatDuration(Duration(milliseconds: durationMs));
}
