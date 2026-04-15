import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Widget that locks the app after a period of inactivity, requiring
/// a PIN to unlock.
///
/// Wraps the app's root widget and monitors user interaction. After
/// [timeoutMinutes] of no touch/click/keyboard activity, a PIN screen
/// is shown that blocks access until the correct PIN is entered.
///
/// Implements item 58 from SUGGESTED_IMPROVEMENTS.md:
/// "Add an inactivity timeout that requires a PIN to unlock the app."
class InactivityLock extends StatefulWidget {
  /// The child widget (typically the app's home screen).
  final Widget child;

  /// Minutes of inactivity before the lock screen appears.
  final int timeoutMinutes;

  /// Whether the lock feature is enabled.
  final bool enabled;

  /// The PIN required to unlock. If null, the lock is disabled.
  final String? pin;

  const InactivityLock({
    super.key,
    required this.child,
    this.timeoutMinutes = 5,
    this.enabled = false,
    this.pin,
  });

  @override
  State<InactivityLock> createState() => _InactivityLockState();
}

class _InactivityLockState extends State<InactivityLock> {
  Timer? _timer;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    _timer?.cancel();
    if (!widget.enabled || widget.pin == null || widget.pin!.isEmpty) return;

    _timer = Timer(
      Duration(minutes: widget.timeoutMinutes),
      () {
        if (mounted && widget.enabled) {
          setState(() => _isLocked = true);
        }
      },
    );
  }

  void _onUserActivity() {
    if (!_isLocked) {
      _resetTimer();
    }
  }

  void _unlock() {
    setState(() => _isLocked = false);
    _resetTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocked) {
      return _PinScreen(
        onUnlock: _unlock,
        expectedPin: widget.pin!,
      );
    }

    return Listener(
      onPointerDown: (_) => _onUserActivity(),
      onPointerMove: (_) => _onUserActivity(),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (_) => _onUserActivity(),
        child: widget.child,
      ),
    );
  }
}

/// PIN entry screen shown when the app is locked.
class _PinScreen extends StatefulWidget {
  final VoidCallback onUnlock;
  final String expectedPin;

  const _PinScreen({
    required this.onUnlock,
    required this.expectedPin,
  });

  @override
  State<_PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<_PinScreen> {
  String _enteredPin = '';
  bool _error = false;
  int _attempts = 0;
  // Enforced cooldown while an attacker is brute-forcing the PIN. Doubles
  // after every failed attempt, capped at 60 seconds. The keypad is
  // disabled while [_cooldownUntil] is in the future.
  DateTime? _cooldownUntil;

  bool get _isLockedOut =>
      _cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!);

  Duration get _remainingLockout => _cooldownUntil == null
      ? Duration.zero
      : _cooldownUntil!.difference(DateTime.now());

  void _addDigit(String digit) {
    if (_isLockedOut) return;
    if (_enteredPin.length >= 6) return;
    setState(() {
      _enteredPin += digit;
      _error = false;
    });

    // Auto-submit when PIN length matches expected.
    if (_enteredPin.length == widget.expectedPin.length) {
      _checkPin();
    }
  }

  void _removeDigit() {
    if (_isLockedOut) return;
    if (_enteredPin.isEmpty) return;
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _error = false;
    });
  }

  void _checkPin() {
    // Constant-time comparison to prevent timing attacks.
    bool match = _enteredPin.length == widget.expectedPin.length;
    int diff = 0;
    for (int i = 0;
        i < _enteredPin.length && i < widget.expectedPin.length;
        i++) {
      diff |= _enteredPin.codeUnitAt(i) ^ widget.expectedPin.codeUnitAt(i);
    }
    match = match && diff == 0;

    if (match) {
      _attempts = 0;
      _cooldownUntil = null;
      widget.onUnlock();
    } else {
      _attempts++;
      // Exponential backoff: 0, 1, 2, 4, 8, ... capped at 60 seconds.
      final int backoffSeconds =
          _attempts < 3 ? 0 : (1 << (_attempts - 3)).clamp(1, 60);
      _cooldownUntil = backoffSeconds == 0
          ? null
          : DateTime.now().add(Duration(seconds: backoffSeconds));
      setState(() {
        _enteredPin = '';
        _error = true;
      });
      HapticFeedback.heavyImpact();
      if (_cooldownUntil != null) {
        Future.delayed(Duration(seconds: backoffSeconds), () {
          if (mounted) setState(() {});
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock, size: 64, color: Colors.white70),
                const SizedBox(height: 16),
                const Text(
                  'Zegel is Locked',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isLockedOut
                      ? 'Too many attempts. Wait ${_remainingLockout.inSeconds + 1}s.'
                      : (_error
                          ? 'Incorrect PIN. Try again.'
                          : 'Enter your PIN to unlock'),
                  style: TextStyle(
                    color: _error || _isLockedOut
                        ? Colors.red.shade300
                        : Colors.white60,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),

                // PIN dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.expectedPin.length,
                    (i) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _enteredPin.length
                            ? (_error ? Colors.red : Colors.tealAccent)
                            : Colors.white24,
                        border: Border.all(
                          color: _error ? Colors.red : Colors.white38,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // Number pad
                ..._buildNumberPad(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNumberPad() {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];

    return rows.map((row) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((key) {
            if (key.isEmpty) {
              return const SizedBox(width: 80, height: 60);
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 80,
                height: 60,
                child: TextButton(
                  onPressed: key == 'del' ? _removeDigit : () => _addDigit(key),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white10,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: key == 'del'
                      ? const Icon(Icons.backspace_outlined,
                          color: Colors.white70, size: 22)
                      : Text(
                          key,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }).toList();
  }
}
