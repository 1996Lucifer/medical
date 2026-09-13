import 'dart:async';

import 'package:flutter/material.dart';

import '../network/rfid_service.dart';

enum _Phase { preparing, needsSetup, ready, waitingForTap, success, failed }

/// Opens RFID card enrollment as a modal dialog over whatever screen the
/// admin is currently on. Enrollment always happens at the one fixed writer
/// station at the admin desk (the same place face enrollment happens), so
/// there's no device picker here. That station is provisioned entirely
/// outside this app: a fixed pre-shared key lives in the backend's
/// `RFID_STATION_DEVICE_KEY` env var (see routers/rfid.py's
/// `ensure_fixed_station`) and the exact same value is flashed into the
/// ESP32's firmware/setup portal once, by whoever installs the hardware.
/// This dialog only ever *looks* for that station — it never generates a
/// key or shows one, so nobody doing routine staff-card enrollment can ever
/// be ambushed with a device key and a firmware-flashing instruction.
Future<void> showRfidEnrollDialog(
  BuildContext context, {
  required int staffId,
  required String staffName,
  String? staffRole,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _RfidEnrollDialog(
      staffId: staffId,
      staffName: staffName,
      staffRole: staffRole,
    ),
  );
}

class _RfidEnrollDialog extends StatefulWidget {
  final int staffId;
  final String staffName;
  final String? staffRole;

  const _RfidEnrollDialog({
    required this.staffId,
    required this.staffName,
    this.staffRole,
  });

  @override
  State<_RfidEnrollDialog> createState() => _RfidEnrollDialogState();
}

class _RfidEnrollDialogState extends State<_RfidEnrollDialog>
    with SingleTickerProviderStateMixin {
  final _rfidService = RfidService();
  late final AnimationController _pulseController;

  RfidDevice? _station;
  String? _loadError;

  _Phase _phase = _Phase.preparing;
  int? _sessionId;
  DateTime? _expiresAt;
  Timer? _pollTimer;
  Timer? _tickTimer;
  int _secondsLeft = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _ensureStation();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  /// The admin desk only ever has one writer station, provisioned entirely
  /// server-side from `RFID_STATION_DEVICE_KEY` (see `ensure_fixed_station`
  /// in routers/rfid.py). This just looks for it — if it's missing, that
  /// means the env var isn't set (or the backend hasn't been restarted
  /// since it was), not something fixable from inside this dialog.
  Future<void> _ensureStation() async {
    setState(() {
      _phase = _Phase.preparing;
      _loadError = null;
    });
    try {
      final devices = await _rfidService.fetchDevices();
      final active = devices.where((d) => d.isActive).toList();
      if (!mounted) return;
      setState(() {
        if (active.isNotEmpty) {
          _station = active.first;
          _phase = _Phase.ready;
        } else {
          _station = null;
          _phase = _Phase.needsSetup;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not check the enrollment station: $e';
        _phase = _Phase.needsSetup;
      });
    }
  }

  Future<void> _startEnrollment() async {
    if (_station == null) return;
    setState(() {
      _errorMessage = null;
      _phase = _Phase.waitingForTap;
    });
    try {
      final result = await _rfidService.createEnrollSession(
        deviceId: _station!.id,
        staffId: widget.staffId,
      );
      _sessionId = result['session_id'] as int;
      _expiresAt = DateTime.parse(result['expires_at'] as String);
      _beginPolling();
      _beginCountdown();
    } catch (e) {
      setState(() {
        _phase = _Phase.failed;
        _errorMessage = 'Could not start enrollment: $e';
      });
    }
  }

  void _beginCountdown() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _expiresAt == null) return;
      final left = _expiresAt!.difference(DateTime.now().toUtc()).inSeconds;
      setState(() => _secondsLeft = left.clamp(0, 999));
    });
  }

  void _beginPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_sessionId == null) return;
      try {
        final status = await _rfidService.getEnrollSessionStatus(_sessionId!);
        if (!mounted) return;
        if (status['consumed'] == true) {
          _pollTimer?.cancel();
          _tickTimer?.cancel();
          setState(() => _phase = _Phase.success);
        } else if (status['expired'] == true) {
          _pollTimer?.cancel();
          _tickTimer?.cancel();
          setState(() {
            _phase = _Phase.failed;
            _errorMessage = 'No card was placed on the reader in time.';
          });
        }
      } catch (_) {}
    });
  }

  void _retry() {
    setState(() {
      _phase = _Phase.ready;
      _sessionId = null;
      _expiresAt = null;
      _errorMessage = null;
    });
  }

  Future<void> _confirmResetStation() async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surfaceContainer,
        title:
            Text('Reset Station?', style: TextStyle(color: scheme.onSurface)),
        content: Text(
          'This restarts the physical RFID station and clears its WiFi/'
          'backend config - it will be offline for about 15-30 seconds and '
          'will need its setup portal filled in again afterward. Only do '
          'this if the station is misbehaving.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset Station'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _rfidService.resetStationConfig();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Station is restarting into its setup portal.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not reset station: $e'),
          backgroundColor: scheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.secondary;

    return Dialog(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: accent.withValues(alpha: 0.3)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(scheme, accent),
            Flexible(
              child: SingleChildScrollView(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 560;
                    final scanPanel = _buildScanPanel(scheme, accent);
                    final infoPanel =
                        _buildInfoPanel(scheme, accent, fillHeight: !narrow);
                    if (narrow) {
                      return Column(children: [scanPanel, infoPanel]);
                    }
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 5, child: scanPanel),
                          VerticalDivider(
                              width: 1, color: scheme.outlineVariant),
                          Expanded(flex: 7, child: infoPanel),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Icon(Icons.nfc, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Enroll RFID Card',
                style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          IconButton(
            icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
            onPressed: () {
              _pollTimer?.cancel();
              _tickTimer?.cancel();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScanPanel(ColorScheme scheme, Color accent) {
    final isWaiting = _phase == _Phase.waitingForTap;
    final isSuccess = _phase == _Phase.success;
    final isFailed = _phase == _Phase.failed;

    IconData icon = Icons.nfc;
    Color iconColor = accent;
    if (isSuccess) {
      icon = Icons.check_circle;
      iconColor = accent;
    } else if (isFailed) {
      icon = Icons.error_outline;
      iconColor = scheme.error;
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isWaiting)
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) {
                      final t = _pulseController.value;
                      return Container(
                        width: 120 + (t * 70),
                        height: 120 + (t * 70),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accent.withValues(alpha: (1 - t) * 0.5),
                          ),
                        ),
                      );
                    },
                  ),
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.surfaceContainerLowest,
                    border: Border.all(color: accent.withValues(alpha: 0.4)),
                  ),
                  child: Icon(icon, size: 44, color: iconColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isWaiting
                ? 'Place the card on the reader'
                : isSuccess
                    ? 'Card Enrolled'
                    : isFailed
                        ? 'Enrollment Failed'
                        : switch (_phase) {
                            _Phase.needsSetup => 'Station Not Configured',
                            _ => 'Ready to Enroll',
                          },
            textAlign: TextAlign.center,
            style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 15),
          ),
          if (isWaiting) ...[
            const SizedBox(height: 8),
            Text('$_secondsLeft s remaining',
                style: TextStyle(
                    color: _secondsLeft <= 15
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoPanel(ColorScheme scheme, Color accent,
      {required bool fillHeight}) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Text('TARGET PERSONNEL',
              style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: accent.withValues(alpha: 0.15),
                  child: Text(
                    widget.staffName.isNotEmpty
                        ? widget.staffName[0].toUpperCase()
                        : '?',
                    style:
                        TextStyle(color: accent, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.staffName,
                          style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      if (widget.staffRole != null)
                        Text(widget.staffRole!,
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_station != null) ...[
            Row(
              children: [
                Icon(Icons.dns_outlined,
                    size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_station!.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12)),
                ),
                // Only offered while nothing's mid-flight - restarting the
                // station under an active enroll session would just orphan
                // it. Reaches the device directly over the LAN, via the
                // backend, so no physical BOOT-button access is needed.
                if (_phase == _Phase.ready)
                  InkWell(
                    onTap: _confirmResetStation,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.restart_alt,
                          size: 14, color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (_phase == _Phase.needsSetup)
            _buildNeedsSetupNotice(scheme, accent),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_loadError!,
                  style: TextStyle(color: scheme.error, fontSize: 12)),
            ),
          if (fillHeight) const Spacer() else const SizedBox(height: 20),
          const SizedBox(height: 16),
          _buildActions(scheme, accent),
        ],
      ),
    );
  }

  /// Shown when no active station is found. This never happens as a result
  /// of anything in this app — the station is provisioned entirely by
  /// setting `RFID_STATION_DEVICE_KEY` in the backend's `.env` and flashing
  /// the same value into the ESP32 firmware, once, at install time (see
  /// `ensure_fixed_station` in routers/rfid.py). This screen just explains
  /// that and offers a retry, for after that's been done and the backend
  /// restarted.
  Widget _buildNeedsSetupNotice(ColorScheme scheme, Color accent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No RFID station is configured.',
            style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'This is a one-time hardware setup step done outside this app: '
            'set RFID_STATION_DEVICE_KEY in the backend\'s .env, flash the '
            'same key into the ESP32\'s firmware, and restart the backend. '
            'Ask whoever installed the reader if this is unexpected.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(ColorScheme scheme, Color accent) {
    switch (_phase) {
      case _Phase.preparing:
        return const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case _Phase.needsSetup:
        // Configuring the station happens outside this app entirely (env
        // var + firmware flash + backend restart) — this can only ever
        // retry the check, never create a device itself.
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            onPressed: _ensureStation,
          ),
        );
      case _Phase.ready:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.nfc),
            label: const Text('Start Enrollment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: scheme.surfaceContainerLowest,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _station != null ? _startEnrollment : null,
          ),
        );
      case _Phase.waitingForTap:
        return TextButton(
          onPressed: () {
            _pollTimer?.cancel();
            _tickTimer?.cancel();
            _retry();
          },
          child:
              Text('Cancel', style: TextStyle(color: scheme.onSurfaceVariant)),
        );
      case _Phase.success:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: scheme.surfaceContainerLowest,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        );
      case _Phase.failed:
        return Column(
          children: [
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_errorMessage!,
                    style: TextStyle(color: scheme.error, fontSize: 12)),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Skip for now'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: scheme.surfaceContainerLowest,
                    ),
                    onPressed: _retry,
                    child: const Text('Try Again'),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }
}
