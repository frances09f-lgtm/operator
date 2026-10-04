import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:friday_app/core/errors/app_exceptions.dart';
import 'package:friday_app/features/assistant/domain/intent_model.dart';
import 'package:friday_app/features/assistant/domain/intent_parser.dart';
import 'package:friday_app/features/assistant/domain/response_generator.dart';
import 'package:friday_app/features/gmail/gmail_service.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;

void main() {
  group('Gmail - IntentParser', () {
    test('parses read_email JSON', () {
      final intent = IntentParser()
          .parse('{"action": "read_email", "target": "unread"}');
      expect(intent, isA<ReadEmailIntent>());
      expect((intent as ReadEmailIntent).count, 5);
    });

    test('parses read_email with count', () {
      final intent = IntentParser()
          .parse('{"action": "check_inbox", "count": 3}');
      expect(intent, isA<ReadEmailIntent>());
      expect((intent as ReadEmailIntent).count, 3);
    });
  });

  group('Gmail - FakeGmailService', () {
    test('requires connection before listing', () async {
      final svc = FakeGmailService(connected: false);
      expect(svc.isConnected(), completion(isFalse));
      expect(
        svc.listUnread(),
        throwsA(isA<Exception>()),
      );
    });

    test('lists unread when connected', () async {
      final svc = FakeGmailService(connected: true);
      final mails = await svc.listUnread(count: 2);
      expect(mails.length, 2);
      expect(mails.first.from, 'Boss');
    });
  });

  group('Gmail - ResponseGenerator', () {
    test('emailsListed formats lines', () {
      const r = ResponseGenerator();
      final msg = r.emailsListed(['1. Boss — Meeting at 4pm.']);
      expect(msg, contains('1 unread mail'));
      expect(r.gmailNotConnected(), contains('not connected'));
      expect(r.gmailNeedsInternet(), contains('internet'));
    });
  });

  group('Gmail - mapGmailFailure', () {
    test('platform network_error becomes a network exception', () {
      final e = mapGmailFailure(
          PlatformException(code: 'network_error', message: 'no net'));
      expect(e, isA<GmailNetworkException>());
    });

    test('platform sign_in_failed explains the Google Cloud setup', () {
      final e = mapGmailFailure(
          PlatformException(code: 'sign_in_failed', message: 'boom'));
      expect(e, isA<GmailException>());
      expect((e as GmailException).message, GmailErrors.setupIncomplete);
    });

    test('cancelled sign-in is reported as cancelled', () {
      final e = mapGmailFailure(PlatformException(code: 'sign_in_canceled'));
      expect((e as GmailException).message, contains('cancelled'));
    });

    test('403 access blocked explains the Google Cloud setup', () {
      final e = mapGmailFailure(gmail.DetailedApiRequestError(
        403,
        'Access blocked: Authorization error [accessNotConfigured]',
      ));
      expect((e as GmailException).message, GmailErrors.setupIncomplete);
      expect(e.detail, contains('403'));
    });

    test('401 means the grant expired and needs reconnecting', () {
      final e = mapGmailFailure(
          gmail.DetailedApiRequestError(401, 'Invalid Credentials'));
      expect((e as GmailException).message, GmailErrors.sessionExpired);
    });

    test('disabled Gmail API is called out', () {
      final e = mapGmailFailure(gmail.DetailedApiRequestError(
          403, 'Gmail API has not been used in project 42 before or it is disabled'));
      expect((e as GmailException).message, GmailErrors.apiDisabled);
    });

    test('insufficient scopes ask for a reconnect', () {
      final e = mapGmailFailure(gmail.DetailedApiRequestError(
          403, 'Request had insufficient authentication scopes'));
      expect((e as GmailException).message, GmailErrors.missingScope);
    });

    test('socket failures are treated as offline', () {
      expect(
        mapGmailFailure(
            Exception('SocketException: Failed host lookup: gmail.googleapis.com')),
        isA<GmailNetworkException>(),
      );
    });

    test('unknown failures keep the generic line but carry a detail', () {
      final e = mapGmailFailure(Exception('something odd'));
      expect((e as GmailException).message, contains("couldn't check"));
      expect(e.detail, contains('something odd'));
    });

    test('existing AppExceptions pass through untouched', () {
      const original = GmailNotConnectedException();
      expect(identical(mapGmailFailure(original), original), isTrue);
    });
  });

  group('Gmail - OAuthConfig', () {
    test('reads client ids from --dart-define', () {
      const empty = GmailOAuthConfig();
      expect(empty.isConfigured, isFalse);
      expect(empty.serverClientId, isNull);
      expect(const GmailOAuthConfig(serverClientId: 'abc').isConfigured, isTrue);
      expect(GmailOAuthConfig.fromEnvironment().isConfigured, isFalse,
          reason: 'tests build without --dart-define');
    });
  });
}
