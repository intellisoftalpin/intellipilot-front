/// One parsed Server-Sent-Events frame.
///
/// `event` is the SSE event name (`change` / `resync` from the backend). The
/// IO transport additionally surfaces server keep-alive comments as
/// `heartbeat` frames so its liveness watchdog can observe them.
class SseFrame {
  const SseFrame({required this.event, required this.data});
  final String event;
  final String data;
}
