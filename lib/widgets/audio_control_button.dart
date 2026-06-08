import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/audio_settings_service.dart';
import '../utils/bgm_service.dart';
import '../utils/sfx_service.dart';

enum AudioControlStyle { appBar, onboarding }

class AudioControlButton extends StatelessWidget {
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
            final color = style == AudioControlStyle.onboarding
                ? (allMuted ? Colors.grey.shade600 : accent)
                : Colors.grey.shade800;
            return _AudioCircle(
              style: style,
              accent: accent,
              child: IconButton(
                icon: Icon(icon, color: color),
                tooltip: '聲音設定',
                onPressed: () => _showAudioSheet(context),
              ),
            );
          },
        );
      },
    );
  }

  void _showAudioSheet(BuildContext context) {
    unawaited(SfxService.instance.play(SfxCue.tap));
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _AudioSettingsSheet(accent: accent, onMusicEnabled: onMusicEnabled),
    );
  }
}

class _AudioCircle extends StatelessWidget {
  final AudioControlStyle style;
  final Color accent;
  final Widget child;

  const _AudioCircle({
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: onboarding ? 0.82 : 0.88),
          shape: BoxShape.circle,
          border: onboarding
              ? Border.all(color: accent.withValues(alpha: 0.22))
              : null,
          boxShadow: [
            BoxShadow(
              color: (onboarding ? accent : Colors.black).withValues(
                alpha: onboarding ? 0.12 : 0.10,
              ),
              blurRadius: onboarding ? 14 : 10,
              offset: Offset(0, onboarding ? 5 : 3),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _AudioSettingsSheet extends StatelessWidget {
  final Color accent;
  final VoidCallback? onMusicEnabled;

  const _AudioSettingsSheet({required this.accent, this.onMusicEnabled});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                _AudioRow(
                  icon: Icons.music_note_rounded,
                  title: '背景音樂',
                  subtitle: '兔咪陪伴的環境音',
                  accent: accent,
                  valueListenable: AudioSettingsService.musicMuted,
                  onChanged: (muted) async {
                    await BgmService.instance.setMuted(muted);
                    if (!muted) onMusicEnabled?.call();
                  },
                ),
                const SizedBox(height: 10),
                _AudioRow(
                  icon: Icons.touch_app_rounded,
                  title: '操作音效',
                  subtitle: '完成、點擊與取消回饋',
                  accent: accent,
                  valueListenable: AudioSettingsService.sfxMuted,
                  onChanged: (muted) async {
                    await AudioSettingsService.instance.setSfxMuted(muted);
                    if (!muted) {
                      unawaited(SfxService.instance.play(SfxCue.success));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final ValueNotifier<bool> valueListenable;
  final Future<void> Function(bool muted) onChanged;

  const _AudioRow({
    required this.icon,
    required this.title,
    required this.subtitle,
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
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: enabled
                ? accent.withValues(alpha: 0.08)
                : Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled
                  ? accent.withValues(alpha: 0.22)
                  : Colors.grey.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: enabled ? accent : Colors.grey.shade400,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                activeThumbColor: accent,
                onChanged: (value) => unawaited(onChanged(!value)),
              ),
            ],
          ),
        );
      },
    );
  }
}
