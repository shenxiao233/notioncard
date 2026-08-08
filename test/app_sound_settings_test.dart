import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kncard_app/core/sound/app_sound_settings.dart';

void main() {
  test('sound settings default to enabled and persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = AppSoundSettingsController(preferences);

    expect(settings.state.enabled, isTrue);
    expect(settings.state.reviewFeedbackEnabled, isTrue);

    await settings.setEnabled(false);
    await settings.setReviewFeedbackEnabled(false);

    expect(preferences.getBool(appSoundEnabledKey), isFalse);
    expect(preferences.getBool(reviewSoundEnabledKey), isFalse);
    expect(settings.state.enabled, isFalse);
    expect(settings.state.reviewFeedbackEnabled, isFalse);
  });
}
