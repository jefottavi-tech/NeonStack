import 'package:flutter/material.dart';

import '../services/progress_store.dart';
import '../services/sound_service.dart';
import 'game_screen.dart';
import 'palette.dart';
import 'services.dart';
import 'tower_painter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  final _stars = Starfield(5);

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _play(int level) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GameScreen(startLevel: level)));
    if (mounted) setState(() {}); // refresh best score and checkpoint
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final ProgressStore progress = services.progress;
    final SoundService sound = services.sound;
    final checkpoint = progress.checkpoint;
    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: DecorTowerPainter(_spin, _stars)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('NEON', textAlign: TextAlign.center, style: neon(64, color: hot, spacing: 14)),
                      Text('STACK', textAlign: TextAlign.center, style: neon(64, spacing: 12)),
                      const SizedBox(height: 8),
                      Text('One tap. One floor. Go higher.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), letterSpacing: 1)),
                      const SizedBox(height: 36),
                      Row(
                        children: [
                          _Stat(label: 'BEST SCORE', value: '${progress.bestScore}'),
                          _Stat(label: 'BEST LEVEL', value: '${progress.bestLevel}'),
                          _Stat(label: 'BOSSES', value: '${progress.bossesBeaten}'),
                        ],
                      ),
                      const SizedBox(height: 32),
                      if (checkpoint > 1) ...[
                        FilledButton(
                          key: const Key('continue-run'),
                          onPressed: () => _play(checkpoint),
                          style: _primary,
                          child: Text('CONTINUE · LEVEL $checkpoint', style: _label),
                        ),
                        const SizedBox(height: 12),
                      ],
                      (checkpoint > 1 ? OutlinedButton.new : FilledButton.new)(
                        key: const Key('play'),
                        onPressed: () => _play(1),
                        style: checkpoint > 1 ? _secondary : _primary,
                        child: Text(checkpoint > 1 ? 'NEW GAME' : 'PLAY', style: _label),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Tap (or Space) to drop the sliding block\n'
                        'Overhang is sliced off · line it up for a PERFECT\n'
                        'Perfects in a row grow the block back\n'
                        'Reach the finish line · 3 lives per level\n'
                        'Every 5th level: a guardian. Perfects hurt it.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.45), height: 1.6, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: IconButton(
                          tooltip: sound.muted ? 'Sound off' : 'Sound on',
                          onPressed: () async {
                            await sound.setMuted(!sound.muted);
                            setState(() {});
                          },
                          icon: Icon(sound.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white54),
                        ),
                      ),
                      Text('Kallistesoft', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _label = TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 2);
  static final _shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  static final _primary = FilledButton.styleFrom(
    backgroundColor: accent,
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(vertical: 18),
    shape: _shape,
  );
  static final _secondary = OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    side: const BorderSide(color: Colors.white30),
    padding: const EdgeInsets.symmetric(vertical: 18),
    shape: _shape,
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: neon(22, color: Colors.white, spacing: 1)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: Colors.white.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}
