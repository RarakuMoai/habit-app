import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/app_style.dart';
import '../utils/audio_settings_service.dart';
import '../utils/bgm_service.dart';
import '../utils/sfx_service.dart';

enum AudioControlStyle { appBar, onboarding }

class AudioControlButton extends StatefulWidget {
  final AudioControlStyle style;
  final Color accent;
  final VoidCallback? onMusicEnabled;

  const AudioControlButton({
    super.key,
    required this.style,
    required this.accent,
    this.onMusicEnabled,
  });

  @override
  State<AudioControlButton> createState() => _AudioControlButtonState();
}

class _AudioControlButtonState extends State<AudioControlButton> {
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _hidePanel(updateState: false);
    super.dispose();
  }

  void _togglePanel() {
    if (_entry != null) {
      _hidePanel();
      return;
    }
    unawaited(SfxService.instance.play(SfxCue.tap));

    final buttonBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    if (buttonBox == null) return;

    final buttonTopLeft = buttonBox.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );
    final overlaySize = overlay.size;
    final panelWidth = overlaySize.width < 192 ? overlaySize.width - 20 : 172.0;
    const panelHeight = 92.0;
    final buttonCenterX = buttonTopLeft.dx + buttonBox.size.width / 2;
    final left = (buttonCenterX - panelWidth / 2).clamp(
      10.0,
      overlaySize.width - panelWidth - 10,
    );
    final arrowX = (buttonCenterX - left).clamp(24.0, panelWidth - 24);
    final below = buttonTopLeft.dy + buttonBox.size.height + 8;
    final top = (below + panelHeight > overlaySize.height - 12)
        ? (buttonTopLeft.dy - panelHeight - 8).clamp(12.0, overlaySize.height)
        : below;

    _entry = OverlayEntry(
      builder: (_) => _AudioPanelOverlay(
        top: top,
        left: left,
        width: panelWidth,
        arrowX: arrowX,
        accent: widget.accent,
        onDismiss: _hidePanel,
        onMusicEnabled: widget.onMusicEnabled,
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _hidePanel({bool updateState = true}) {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioSettingsService.musicMuted,
      builder: (_, musicMuted, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AudioSettingsService.sfxMuted,
          builder: (_, sfxMuted, _) {
            final allMuted = musicMuted && sfxMuted;
            final icon = allMuted
                ? Icons.volume_off_rounded
                : (musicMuted || sfxMuted
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded);
            final color = widget.style == AudioControlStyle.onboarding
                ? (allMuted ? AppInk.soft : widget.accent)
                : AppInk.strong;
            return _AudioCircle(
              key: _buttonKey,
              style: widget.style,
              accent: widget.accent,
              child: IconButton(
                icon: Icon(icon, color: color),
                tooltip: '聲音設定',
                onPressed: _togglePanel,
              ),
            );
          },
        );
      },
    );
  }
}

class _AudioCircle extends StatelessWidget {
  final AudioControlStyle style;
  final Color accent;
  final Widget child;

  const _AudioCircle({
    super.key,
    required this.style,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final onboarding = style == AudioControlStyle.onboarding;
    return Padding(
      padding: onboarding
          ? const EdgeInsets.only(top: 6, right: 10)
          : const EdgeInsets.only(right: 4),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: onboarding ? 0.82 : 0.88),
            shape: BoxShape.circle,
            border: onboarding
                ? Border.all(color: accent.withValues(alpha: 0.22))
                : null,
            boxShadow: [
              BoxShadow(
                color: (onboarding ? accent : const Color(0xFF8D6E63))
                    .withValues(alpha: onboarding ? 0.12 : 0.22),
                blurRadius: onboarding ? 14 : 10,
                offset: Offset(0, onboarding ? 5 : 3),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _AudioPanelOverlay extends StatelessWidget {
  final double top;
  final double left;
  final double width;
  final double arrowX;
  final Color accent;
  final VoidCallback onDismiss;
  final VoidCallback? onMusicEnabled;

  const _AudioPanelOverlay({
    required this.top,
    required this.left,
    required this.width,
    required this.arrowX,
    required this.accent,
    required this.onDismiss,
    this.onMusicEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          top: top,
          left: left,
          width: width,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutQuart,
            builder: (_, t, _) {
              final eased = Curves.easeOutCubic.transform(t);
              return Opacity(
                opacity: eased,
                child: Transform.scale(
                  alignment: Alignment((arrowX / width) * 2 - 1, -1),
                  scaleX: 0.18 + eased * 0.82,
                  scaleY: 0.62 + eased * 0.38,
                  child: Material(
                    color: Colors.transparent,
                    child: _AudioSettingsPanel(
                      accent: accent,
                      arrowX: arrowX,
                      flowProgress: t,
                      onMusicEnabled: onMusicEnabled,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AudioSettingsPanel extends StatelessWidget {
  final Color accent;
  final double arrowX;
  final double flowProgress;
  final VoidCallback? onMusicEnabled;

  const _AudioSettingsPanel({
    required this.accent,
    required this.arrowX,
    required this.flowProgress,
    this.onMusicEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -7,
          left: arrowX - 9,
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.97),
                border: Border(
                  left: BorderSide(color: accent.withValues(alpha: 0.14)),
                  top: BorderSide(color: accent.withValues(alpha: 0.14)),
                ),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8D6E63).withValues(alpha: 0.30),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FlowReveal(
                  progress: flowProgress,
                  delay: 0.12,
                  child: _AudioTile(
                    icon: Icons.music_note_rounded,
                    title: '音樂',
                    accent: accent,
                    valueListenable: AudioSettingsService.musicMuted,
                    onChanged: (muted) async {
                      await BgmService.instance.setMuted(muted);
                      if (!muted) onMusicEnabled?.call();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _FlowReveal(
                  progress: flowProgress,
                  delay: 0.24,
                  child: _AudioTile(
                    icon: Icons.touch_app_rounded,
                    title: '音效',
                    accent: accent,
                    valueListenable: AudioSettingsService.sfxMuted,
                    onChanged: (muted) async {
                      if (muted) {
                        unawaited(SfxService.instance.play(SfxCue.tap));
                        await Future<void>.delayed(
                          const Duration(milliseconds: 80),
                        );
                      }
                      await AudioSettingsService.instance.setSfxMuted(muted);
                      if (!muted) {
                        unawaited(SfxService.instance.play(SfxCue.success));
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FlowReveal extends StatelessWidget {
  final double progress;
  final double delay;
  final Widget child;

  const _FlowReveal({
    required this.progress,
    required this.delay,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final local = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(local);
    return Opacity(
      opacity: eased,
      child: Transform.translate(
        offset: Offset(0, (1 - eased) * -8),
        child: child,
      ),
    );
  }
}

class _AudioTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color accent;
  final ValueNotifier<bool> valueListenable;
  final Future<void> Function(bool muted) onChanged;

  const _AudioTile({
    required this.icon,
    required this.title,
    required this.accent,
    required this.valueListenable,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: valueListenable,
      builder: (_, muted, _) {
        final enabled = !muted;
        return Semantics(
          button: true,
          toggled: enabled,
          label: title,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(onChanged(enabled)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOutCubic,
              width: 74,
              height: 66,
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
              decoration: BoxDecoration(
                color: enabled
                    ? accent.withValues(alpha: 0.11)
                    : AppInk.faint.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: enabled
                      ? accent.withValues(alpha: 0.26)
                      : AppInk.faint.withValues(alpha: 0.30),
                ),
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 170),
                      curve: Curves.easeOutCubic,
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: enabled ? accent : AppInk.faint,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: Colors.white, size: 17),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 170),
                      curve: Curves.easeOutCubic,
                      width: 19,
                      height: 19,
                      decoration: BoxDecoration(
                        color: enabled
                            ? accent.withValues(alpha: 0.16)
                            : AppInk.faint.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        enabled ? Icons.check_rounded : Icons.close_rounded,
                        size: 12.5,
                        color: enabled ? accent : AppInk.soft,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: enabled ? AppInk.strong : AppInk.soft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
