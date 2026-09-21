import 'package:flutter/material.dart';
import 'tracking_signal_service.dart';

/// User transparency banner - shown whenever indoor tracking is active,
/// paused, or was just stopped for the current attendance session. Never
/// silent: the user always sees why their location is (or isn't) being
/// shared, matching the "no covert tracking" requirement.
class TrackingStatusBanner extends StatelessWidget {
  const TrackingStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TrackingBannerState>(
      valueListenable: TrackingSignalService.banner,
      builder: (context, state, _) {
        if (state.status == TrackingBannerStatus.inactive) {
          return const SizedBox.shrink();
        }

        final (icon, color, text) = switch (state.status) {
          TrackingBannerStatus.active => (
              Icons.location_on,
              Colors.teal,
              'Indoor location tracking is active for your hospital attendance session.',
            ),
          TrackingBannerStatus.pausedOutsideGeofence => (
              Icons.pause_circle_outline,
              Colors.orange,
              "Tracking paused — you're outside hospital premises. Resumes automatically when you're back.",
            ),
          TrackingBannerStatus.stopped => (
              Icons.location_off,
              Colors.grey,
              'Indoor location tracking has stopped for this session.',
            ),
          TrackingBannerStatus.inactive => (Icons.location_off, Colors.grey, ''),
        };

        return Material(
          color: color.withValues(alpha: 0.12),
          child: InkWell(
            onTap: () => _showDetails(context, state),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.info_outline, size: 14, color: color.withValues(alpha: 0.7)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDetails(BuildContext context, TrackingBannerState state) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Indoor Location Tracking', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            _row('Status', switch (state.status) {
              TrackingBannerStatus.active => 'Active',
              TrackingBannerStatus.pausedOutsideGeofence => 'Paused — outside hospital premises',
              TrackingBannerStatus.stopped => 'Stopped',
              TrackingBannerStatus.inactive => 'Not tracking',
            }),
            if (state.sessionStartedAt != null)
              _row('Session started', state.sessionStartedAt!.toLocal().toString().substring(0, 16)),
            _row('Reason', 'Active hospital attendance session'),
            const SizedBox(height: 8),
            const Text(
              'What is collected: your connected Wi-Fi network name, and your '
              'device GPS location if you granted permission - only while your '
              'attendance session is open. Nothing is collected after checkout.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }
}
