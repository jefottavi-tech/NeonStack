import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neon_stack/main.dart';
import 'package:neon_stack/services/ad_service.dart';
import 'package:neon_stack/services/progress_store.dart';
import 'package:neon_stack/services/sound_service.dart';

void main() {
  testWidgets('start a game from the home screen, stack a block, pause and quit', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressStore.open();
    final sound = NoSound();
    await tester.pumpWidget(NeonStackApp(progress: progress, ads: const NoAdService(), sound: sound));
    expect(find.text('NEON'), findsOneWidget);

    await tester.tap(find.byKey(const Key('play')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('LEVEL 1'), findsNothing); // intro banner has faded
    expect(find.text('0 / 15'), findsOneWidget);

    // Tap the middle of the screen: a block lands (or misses), either way a sound plays.
    await tester.tapAt(tester.getCenter(find.byType(Scaffold)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(sound.played, anyOf(contains(Sfx.place), contains(Sfx.miss), contains(Sfx.chime1)));

    await tester.tap(find.byKey(const Key('pause')));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    await tester.tap(find.text('Quit to menu'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // the home backdrop never settles
    expect(find.text('NEON'), findsOneWidget);
  });
}
