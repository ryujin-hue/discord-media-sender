import 'package:discord_media_sender/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateService.compareVersions', () {
    test('detects a newer patch version', () {
      expect(UpdateService.compareVersions('2.0.1', '2.0.0'), greaterThan(0));
    });

    test('detects a newer minor version', () {
      expect(UpdateService.compareVersions('2.1.0', '2.0.9'), greaterThan(0));
    });

    test('detects a newer major version', () {
      expect(UpdateService.compareVersions('3.0.0', '2.9.9'), greaterThan(0));
    });

    test('treats equal versions as equal', () {
      expect(UpdateService.compareVersions('2.0.0', '2.0.0'), 0);
    });

    test('treats an older version as smaller', () {
      expect(UpdateService.compareVersions('1.0.9', '2.0.0'), lessThan(0));
    });

    test('compares different segment counts correctly', () {
      expect(UpdateService.compareVersions('2.0', '2.0.0'), 0);
      expect(UpdateService.compareVersions('2.0.1', '2.0'), greaterThan(0));
    });

    test('ignores a build metadata suffix', () {
      expect(UpdateService.compareVersions('2.0.0+20000', '2.0.0'), 0);
    });

    test('handles a pre-release suffix', () {
      expect(
        UpdateService.compareVersions('2.0.0-beta.1', '2.0.0'),
        lessThan(0),
      );
    });
  });

  group('UpdateService.versionCodeFromTag', () {
    test('derives an increasing version code', () {
      expect(UpdateService.versionCodeFromTag('v2.0.0'), 20000);
      expect(UpdateService.versionCodeFromTag('2.0.1'), 20001);
      expect(UpdateService.versionCodeFromTag('v2.1.0'), 20100);
      expect(UpdateService.versionCodeFromTag('v3.0.0'), 30000);
    });

    test('always produces a code above the 1.0 build', () {
      // The 1.0.a9 release used versionCode 15.
      expect(UpdateService.versionCodeFromTag('v2.0.0'), greaterThan(15));
    });

    test('is monotonic for increasing versions', () {
      final List<int> codes = <int>[
        UpdateService.versionCodeFromTag('v2.0.0'),
        UpdateService.versionCodeFromTag('v2.0.1'),
        UpdateService.versionCodeFromTag('v2.1.0'),
        UpdateService.versionCodeFromTag('v3.0.0'),
      ];
      for (int i = 1; i < codes.length; i++) {
        expect(codes[i], greaterThan(codes[i - 1]));
      }
    });
  });

  test('formatNotes falls back to a default message', () {
    expect(UpdateService.formatNotes(null), 'No release notes.');
    expect(UpdateService.formatNotes('  '), 'No release notes.');
    expect(UpdateService.formatNotes('Fixed a bug'), 'Fixed a bug');
  });
}
