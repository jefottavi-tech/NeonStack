import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/levels.dart';
import '../game/world.dart';
import '../services/ad_service.dart';
import '../services/progress_store.dart';
import '../services/sound_service.dart';
import 'ad_slot.dart';
import 'palette.dart';
import 'services.dart';
import 'tower_painter.dart';

enum _Phase { playing, paused, cleared, over }

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.startLevel, this.random});

  final int startLevel;

  /// Seeded in tests.
  final Random? random;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late Run _run = Run(level: widget.startLevel);
  late World _world = World(_run, rng: widget.random);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  final _frame = ValueNotifier(0);
  final _stars = Starfield();
  _Phase _phase = _Phase.playing;
  LevelSummary? _summary;
  bool _newBest = false;

  late ProgressStore _progress;
  late AdService _ads;
  late SoundService _sound;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = Services.of(context);
    _progress = services.progress;
    _ads = services.ads;
    _sound = services.sound;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _phase == _Phase.playing) setState(() => _phase = _Phase.paused);
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _last = elapsed;
    if (_phase != _Phase.playing && _phase != _Phase.over) return;
    _world.update(dt);
    _handleEvents();
    _frame.value++;
  }

  void _drop() {
    if (_phase != _Phase.playing) return;
    if (_world.drop()) _handleEvents();
  }

  void _handleEvents() {
    for (final e in _world.events) {
      switch (e) {
        case GameEvent.place:
          _sound.play(Sfx.place);
        case GameEvent.slice:
          _sound.play(Sfx.slice);
          HapticFeedback.lightImpact();
        case GameEvent.perfect:
          _sound.play(Sfx.chime(_world.streak));
          HapticFeedback.selectionClick();
        case GameEvent.regrow:
          _sound.play(Sfx.regrow);
        case GameEvent.miss:
          _sound.play(Sfx.miss);
          HapticFeedback.heavyImpact();
        case GameEvent.gem:
          _sound.play(Sfx.gem);
        case GameEvent.bossHit:
          _sound.play(Sfx.bossHit);
          HapticFeedback.mediumImpact();
        case GameEvent.bossWarning:
          _sound.play(Sfx.warning);
        case GameEvent.flipWarning:
          _sound.play(Sfx.flip);
        case GameEvent.bossDown:
          _sound.play(Sfx.bossDown);
          HapticFeedback.heavyImpact();
        case GameEvent.levelClear:
          _onCleared();
        case GameEvent.gameOver:
          _onOver();
      }
    }
    _world.events.clear();
  }

  void _onCleared() {
    _sound.play(Sfx.levelClear);
    final next = _run.level + 1;
    _progress.reachLevel(next, LevelSpec.checkpointFor(next));
    if (_world.spec.isBoss) _progress.bossBeaten();
    setState(() {
      _summary = _world.finish();
      _phase = _Phase.cleared;
    });
    _progress.recordScore(_run.score);
  }

  Future<void> _onOver() async {
    _sound.play(Sfx.gameOver);
    setState(() => _phase = _Phase.over);
    await _progress.reachLevel(_run.level, LevelSpec.checkpointFor(_run.level));
    final best = await _progress.recordScore(_run.score);
    if (mounted) setState(() => _newBest = best);
  }

  bool _advancing = false;

  Future<void> _nextLevel() async {
    if (_phase != _Phase.cleared || _advancing) return;
    _advancing = true;
    await _ads.showInterstitial();
    _advancing = false;
    if (!mounted) return;
    setState(() {
      _run.level++;
      _world = World(_run, rng: widget.random);
      _phase = _Phase.playing;
    });
  }

  /// Rewarded ad: back on the same tower with two lives.
  Future<void> _revive() async {
    if (!await _ads.showRewarded() || !mounted) return;
    setState(() {
      _run.revived = true;
      _world.revive();
      _phase = _Phase.playing;
      _newBest = false;
    });
  }

  void _retry() {
    setState(() {
      _run = Run(level: LevelSpec.checkpointFor(_run.level));
      _world = World(_run, rng: widget.random);
      _phase = _Phase.playing;
      _newBest = false;
    });
  }

  void _togglePause() {
    if (_phase == _Phase.playing) {
      setState(() => _phase = _Phase.paused);
    } else if (_phase == _Phase.paused) {
      setState(() => _phase = _Phase.playing);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyP) {
      _togglePause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.arrowDown) {
      if (_phase == _Phase.cleared) {
        _nextLevel();
      } else {
        _drop();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(builder: (context, constraints) {
          final t = FieldTransform(constraints.biggest);
          // Raw pointer-down for zero-latency drops; the top bar (pause button) is left alone.
          final textScale = t.scale.clamp(0.8, 1.6);
          final hudBottom = MediaQuery.paddingOf(context).top + 64 * textScale;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              if (e.localPosition.dy > hudBottom) _drop();
            },
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: TowerPainter(_world, _stars, repaint: _frame))),
                if (_phase == _Phase.playing || _phase == _Phase.paused)
                  Positioned.fill(
                    child: SafeArea(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: ListenableBuilder(listenable: _frame, builder: (context, _) => _hud(textScale)),
                        ),
                      ),
                    ),
                  ),
                if (_phase != _Phase.playing) Positioned.fill(child: _overlay()),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ---- HUD ----

  Widget _hud(double textScale) {
    final w = _world;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 14 * textScale, color: Colors.white, fontWeight: FontWeight.w800),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        key: const Key('pause'),
                        onPressed: _togglePause,
                        icon: const Icon(Icons.pause_rounded),
                        color: Colors.white70,
                        tooltip: 'Pause',
                      ),
                      Text('${_run.score}', key: const Key('score'), style: neon(20 * textScale, color: Colors.white, spacing: 1)),
                      if (w.streak > 1) ...[
                        const SizedBox(width: 8),
                        Text('×${w.streak}', style: neon(14 * textScale, color: gold)),
                      ],
                      const Spacer(),
                      Text('LV ${_run.level}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                      const SizedBox(width: 10),
                      for (var i = 0; i < World.startLives; i++)
                        Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Icon(
                            Icons.favorite_rounded,
                            size: 16 * textScale,
                            color: i < w.lives ? hot : Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 0, 0),
                    child: w.spec.isBoss ? _bossBar(textScale) : _heightBar(textScale),
                  ),
                ],
              ),
            ),
            if (_phase == _Phase.playing) _banner(textScale),
            if (_phase == _Phase.playing && _run.level == 1 && w.height < 2 && w.time > 1.2)
              Positioned(
                left: 0,
                right: 0,
                bottom: 40,
                child: Text('TAP TO DROP', textAlign: TextAlign.center, style: neon(16 * textScale, color: Colors.white70, spacing: 4)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _heightBar(double textScale) {
    final w = _world;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              key: const Key('progress'),
              value: (w.height / w.spec.target).clamp(0.0, 1.0),
              minHeight: 6,
              color: floorColor(w.spec.hue, w.height),
              backgroundColor: Colors.white12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('${w.height} / ${w.spec.target}', style: TextStyle(fontSize: 12 * textScale, color: Colors.white70)),
      ],
    );
  }

  Widget _bossBar(double textScale) {
    final w = _world;
    final color = bossColors[w.spec.boss!.index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(w.spec.name.toUpperCase(), style: neon(11 * textScale, color: color)),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            key: const Key('boss-hp'),
            value: w.bossHp / w.spec.bossHp,
            minHeight: 6,
            color: w.bossFlash > 0 ? Colors.white : color,
            backgroundColor: Colors.white12,
          ),
        ),
      ],
    );
  }

  /// Level intro, or the boss warning, in the upper part of the field.
  Widget _banner(double textScale) {
    final w = _world;
    final spec = w.spec;
    Widget place(Widget child) => Positioned(left: 0, right: 0, top: 120 * textScale, child: child);
    if (spec.isBoss && w.time < World.bossIntro + 0.6) {
      final on = (w.time * 3).floor().isEven;
      final color = bossColors[spec.boss!.index];
      return place(Column(
        children: [
          Text('WARNING', style: neon(34 * textScale, color: on ? hot : hot.withValues(alpha: 0.3), spacing: 8)),
          const SizedBox(height: 8),
          Text(spec.name.toUpperCase(), style: neon(18 * textScale, color: color, spacing: 4)),
          const SizedBox(height: 8),
          Text(bossHints[spec.boss]!, style: TextStyle(fontSize: 13 * textScale, color: Colors.white70)),
          Text('Perfect drops damage it', style: TextStyle(fontSize: 13 * textScale, color: Colors.white54)),
        ],
      ));
    }
    if (spec.isBoss || w.time > 2.4) return const SizedBox.shrink();
    final fade = (w.time < 1.9 ? 1.0 : (2.4 - w.time) / 0.5).clamp(0.0, 1.0);
    return place(IgnorePointer(
      child: Opacity(
        opacity: fade,
        child: Column(
          children: [
            Text('LEVEL ${spec.number}', style: neon(34 * textScale, spacing: 6)),
            const SizedBox(height: 6),
            Text(spec.name.toUpperCase(), style: neon(14 * textScale, color: Colors.white70, spacing: 3)),
            const SizedBox(height: 6),
            Text('STACK ${spec.target} FLOORS', style: TextStyle(fontSize: 12 * textScale, color: Colors.white60, letterSpacing: 2)),
            if (spec.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              _tags(spec, textScale),
            ],
          ],
        ),
      ),
    ));
  }

  Widget _tags(LevelSpec spec, double textScale) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in spec.tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: gold.withValues(alpha: 0.7)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(tag.toUpperCase(), style: TextStyle(fontSize: 11 * textScale, color: gold, letterSpacing: 1.5)),
          ),
      ],
    );
  }

  // ---- overlays ----

  Widget _overlay() {
    final panel = switch (_phase) {
      _Phase.paused => _pausePanel(),
      _Phase.cleared => _clearedPanel(),
      _Phase.over => _overPanel(),
      _Phase.playing => const SizedBox.shrink(),
    };
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: panel),
          ),
        ),
      ),
    );
  }

  Widget _pausePanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('PAUSED', textAlign: TextAlign.center, style: neon(32, spacing: 6)),
        const SizedBox(height: 28),
        _button('Resume', _togglePause, primary: true),
        const SizedBox(height: 12),
        _button(_sound.muted ? 'Sound: off' : 'Sound: on', () async {
          await _sound.setMuted(!_sound.muted);
          setState(() {});
        }),
        const SizedBox(height: 12),
        _button('Quit to menu', () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _clearedPanel() {
    final s = _summary!;
    final spec = _world.spec;
    final next = LevelSpec.forLevel(_run.level + 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(spec.isBoss ? 'GUARDIAN DOWN' : 'LEVEL ${spec.number} CLEAR',
            textAlign: TextAlign.center, style: neon(26, color: spec.isBoss ? gold : accent, spacing: 4)),
        const SizedBox(height: 14),
        _stat('Floors', '${s.floors}'),
        _stat('Perfect drops', '${s.perfects}'),
        _stat('Best streak', '×${s.bestStreak}'),
        if (s.gems > 0) _stat('Gems', '${s.gems}', color: lime),
        _stat('Lives bonus', '+${s.livesBonus}'),
        if (s.flawlessBonus > 0) _stat('Flawless bonus', '+${s.flawlessBonus}', color: gold),
        const Divider(color: Colors.white24, height: 18),
        _stat('Score', '${_run.score}', big: true),
        const SizedBox(height: 14),
        const Center(child: AdSlot()),
        const SizedBox(height: 14),
        Text(
          next.isBoss ? 'GUARDIAN AHEAD: ${next.name.toUpperCase()}' : 'NEXT · LEVEL ${next.number} · ${next.name.toUpperCase()}',
          textAlign: TextAlign.center,
          style: neon(12, color: next.isBoss ? hot : Colors.white70, spacing: 2),
        ),
        if (next.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          _tags(next, 1),
        ],
        const SizedBox(height: 12),
        _button('Continue', _nextLevel, primary: true, key: const Key('continue')),
      ],
    );
  }

  Widget _overPanel() {
    final checkpoint = LevelSpec.checkpointFor(_run.level);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('TOWER DOWN', textAlign: TextAlign.center, style: neon(34, color: hot, spacing: 6)),
        const SizedBox(height: 16),
        _stat('Level', '${_run.level}'),
        if (!_world.spec.isBoss) _stat('Floors', '${_world.height} / ${_world.spec.target}'),
        _stat('Score', '${_run.score}', big: true),
        if (_newBest) Text('NEW BEST', textAlign: TextAlign.center, style: neon(16, color: gold)),
        const SizedBox(height: 24),
        if (!_run.revived) ...[
          _button('Revive · watch an ad', _revive, primary: true, icon: Icons.play_circle_fill_rounded, key: const Key('revive')),
          const SizedBox(height: 12),
        ],
        _button('Retry from level $checkpoint', _retry, primary: _run.revived),
        const SizedBox(height: 12),
        _button('Menu', () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _stat(String label, String value, {bool big = false, Color color = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: Colors.white60, fontSize: big ? 16 : 14)),
          const Spacer(),
          Text(value, style: big ? neon(22, color: color, spacing: 1) : TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap, {bool primary = false, IconData? icon, Key? key}) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1)),
      ],
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const padding = EdgeInsets.symmetric(vertical: 16);
    return primary
        ? FilledButton(
            key: key,
            onPressed: onTap,
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black, shape: shape, padding: padding),
            child: child,
          )
        : OutlinedButton(
            key: key,
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white30),
              shape: shape,
              padding: padding,
            ),
            child: child,
          );
  }
}
