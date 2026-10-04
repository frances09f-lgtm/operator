import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;

import 'package:friday_app/core/errors/app_exceptions.dart';

/// Single mail shown + spoken by FRIDAY (headers + snippet only, no full body
/// in Phase 1 to keep data use low).
class EmailMessage {
  final String id;
  final String from;
  final String subject;
  final String snippet;
  final String date;

  const EmailMessage({
    required this.id,
    required this.from,
    required this.subject,
    required this.snippet,
    this.date = '',
  });
}

/// OAuth client IDs needed by Google Sign-In on Android.
///
/// Supplied at build time so nothing secret lives in the repo:
/// `flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>`
/// The web client id is a *public* identifier, not a secret.
class GmailOAuthConfig {
  final String? serverClientId;
  final String? clientId;

  const GmailOAuthConfig({this.serverClientId, this.clientId});

  /// Reads `--dart-define` values.
  factory GmailOAuthConfig.fromEnvironment() => const GmailOAuthConfig(
        serverClientId: String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
        clientId: String.fromEnvironment('GOOGLE_CLIENT_ID'),
      );

  bool get isConfigured =>
      (serverClientId ?? '').isNotEmpty || (clientId ?? '').isNotEmpty;
}

/// Short, spoken, actionable Gmail failure messages. Kept in one place so the
/// UI and voice always agree.
class GmailErrors {
  static const setupIncomplete =
      'Gmail setup is not finished yet. This app still needs to be registered in Google Cloud.';
  static const apiDisabled =
      'The Gmail API is not enabled in your Google Cloud project yet.';
  static const accessBlocked =
      'Google blocked access. Add this app as a test user in Google Cloud.';
  static const missingScope =
      'Gmail needs read access again. Tap Connect Gmail to reconnect.';
  static const sessionExpired =
      'Gmail sign-in expired. Tap Connect Gmail to reconnect.';
}

/// Turns any Google/Google-API failure into a short spoken sentence plus a
/// technical [detail] for the debug panel.
///
/// Kept top-level and pure so it is unit-testable without a device.
AppException mapGmailFailure(Object error) {
  if (error is AppException) return error;

  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    final text = (error.message ?? '').toLowerCase();
    final detail = 'PlatformException($code): ${error.message}';
    if (code == 'network_error' || text.contains('network')) {
      return const GmailNetworkException();
    }
    if (code == 'sign_in_canceled') {
      return const GmailException('Gmail sign-in was cancelled.');
    }
    return GmailException(GmailErrors.setupIncomplete, detail);
  }

  if (error is gmail.DetailedApiRequestError) {
    return _mapApiError(error.status, _apiDetail(error));
  }
  if (error is gmail.ApiRequestError) {
    final detail = 'ApiRequestError: ${error.message}';
    return _mapText(error.message ?? detail, detail);
  }

  final text = error.toString();
  if (_looksOffline(text)) return const GmailNetworkException();
  return _mapText(text, text);
}

AppException _mapApiError(int? status, String detail) {
  if (status == 401) return GmailException(GmailErrors.sessionExpired, detail);
  if (status == 403) return _mapText(detail, detail, forbidden: true);
  if (status == 429) {
    return GmailException('Gmail is rate-limiting requests. Try again shortly.', detail);
  }
  return _mapText(detail, detail);
}

AppException _mapText(String text, String detail, {bool forbidden = false}) {
  final t = text.toLowerCase();
  if (t.contains('api has not been used') ||
      t.contains('service_disabled') ||
      t.contains('is not enabled') ||
      t.contains('disabling')) {
    return GmailException(GmailErrors.apiDisabled, detail);
  }
  if (t.contains('insufficient') ||
      t.contains('request had insufficient authentication scopes') ||
      t.contains('insufficientpermissions')) {
    return GmailException(GmailErrors.missingScope, detail);
  }
  if (forbidden ||
      t.contains('access_denied') ||
      t.contains('access blocked') ||
      t.contains('invalid_client') ||
      t.contains('unregistered') ||
      t.contains('developer console')) {
    return GmailException(GmailErrors.setupIncomplete, detail);
  }
  return GmailException("I couldn't check your mails. Please try again.", detail);
}

String _apiDetail(gmail.DetailedApiRequestError error) {
  final reasons =
      error.errors.map((e) => e.reason).whereType<String>().join(', ');
  return 'HTTP ${error.status} ${error.message ?? ''}'
      '${reasons.isEmpty ? '' : ' [$reasons]'}';
}

bool _looksOffline(String text) {
  final t = text.toLowerCase();
  return t.contains('socketexception') ||
      t.contains('failed host lookup') ||
      t.contains('nodename nor servname') ||
      t.contains('network is unreachable') ||
      t.contains('connection refused') ||
      t.contains('connection reset') ||
      t.contains('networkerror') ||
      t.contains('timed out') ||
      t.contains('timeout') ||
      t.contains('unreachable') ||
      t.contains('handshake');
}

/// Read-only Gmail access via Official Google Sign-In + Gmail API.
///
/// Flow: [connect] (account picker, `gmail.readonly` scope) -> token stays on
/// device via google_sign_in cache + [FlutterSecureStorage] flag ->
/// [listUnread] runs fully in background over HTTPS, no Gmail app opened.
///
/// Draft/send is Phase 2 (needs extra scopes + explicit voice confirm).
abstract class GmailService {
  /// True when a Google account with Gmail scope is signed in.
  Future<bool> isConnected();

  /// Shows account picker, requests `gmail.readonly`. Throws [GmailException]
  /// when user cancels or sign-in fails.
  Future<void> connect();

  /// Signs out + clears local flag. Never deletes server mail.
  Future<void> disconnect();

  /// Returns up to [count] unread mails (newest first). Throws
  /// [GmailNotConnectedException] when not signed in,
  /// [GmailNetworkException] when offline.
  Future<List<EmailMessage>> listUnread({int count = 5});
}

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner;

  _GoogleAuthClient(this._headers, [http.Client? inner])
      : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}

class GoogleGmailService implements GmailService {
  static const _connectedKey = 'gmail_connected_v1';
  static const List<String> scopes = ['https://www.googleapis.com/auth/gmail.readonly'];

  final GoogleSignIn _signIn;
  final FlutterSecureStorage _storage;
  final GmailOAuthConfig _oauth;
  final http.Client? _httpClient;

  GoogleGmailService({
    GoogleSignIn? signIn,
    FlutterSecureStorage? storage,
    GmailOAuthConfig? oauthConfig,
    http.Client? httpClient,
  })  : _oauth = oauthConfig ?? GmailOAuthConfig.fromEnvironment(),
        _signIn = signIn ?? _defaultSignIn(oauthConfig),
        _storage = storage ?? const FlutterSecureStorage(),
        _httpClient = httpClient;

  static GoogleSignIn _defaultSignIn(GmailOAuthConfig? config) {
    final c = config ?? GmailOAuthConfig.fromEnvironment();
    String? orNull(String? v) => (v == null || v.isEmpty) ? null : v;
    return GoogleSignIn(
      scopes: scopes,
      serverClientId: orNull(c.serverClientId),
      clientId: orNull(c.clientId),
    );
  }

  /// Runs [body], converting any failure into an actionable [AppException] and
  /// writing the raw error to logcat (`friday.gmail`).
  Future<T> _guard<T>(String operation, Future<T> Function() body) async {
    try {
      return await body();
    } catch (error, stack) {
      developer.log('Gmail $operation failed',
          name: 'friday.gmail', error: error, stackTrace: stack, level: 900);
      final mapped = mapGmailFailure(error);
      // No OAuth client id compiled in is the #1 cause of a silent 403 on a
      // fresh install — say so instead of "try again later".
      if (!_oauth.isConfigured && mapped is GmailException) {
        throw GmailException(
          GmailErrors.setupIncomplete,
          '${mapped.detail ?? mapped.message} | no GOOGLE_SERVER_CLIENT_ID '
          '(--dart-define) and no google-services.json in this build',
        );
      }
      throw mapped;
    }
  }

  Future<gmail.GmailApi> _api() async {
    GoogleSignInAccount? account = _signIn.currentUser;
    account ??= await _signIn.signInSilently();
    if (account == null) throw const GmailNotConnectedException();
    final headers = await account.authHeaders;
    return gmail.GmailApi(_GoogleAuthClient(headers, _httpClient));
  }

  @override
  Future<bool> isConnected() async {
    try {
      if (_signIn.currentUser != null) return true;
      final silent = await _signIn.signInSilently();
      if (silent != null) return true;
      final flag = await _storage.read(key: _connectedKey);
      return flag == '1';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> connect() => _guard('connect', () async {
        final account = await _signIn.signIn();
        if (account == null) {
          throw const GmailException('Gmail sign-in was cancelled.');
        }
        // Force token fetch now so failures surface here, not on first read.
        await account.authHeaders;
        await _storage.write(key: _connectedKey, value: '1');
      });

  @override
  Future<void> disconnect() async {
    try {
      await _signIn.disconnect();
    } catch (_) {
      try {
        await _signIn.signOut();
      } catch (_) {}
    }
    try {
      await _storage.delete(key: _connectedKey);
    } catch (_) {}
  }

  @override
  Future<List<EmailMessage>> listUnread({int count = 5}) async {
    final safeCount = count.clamp(1, 10);
    final api = await _guard('open inbox', () => _api());
    return _guard('list unread', () async {
      final list = await api.users.messages.list(
        'me',
        q: 'is:unread',
        maxResults: safeCount,
      );
      final msgs = list.messages ?? [];
      if (msgs.isEmpty) return <EmailMessage>[];
      final out = <EmailMessage>[];
      for (final m in msgs.take(safeCount)) {
        if (m.id == null) continue;
        try {
          final full = await api.users.messages.get(
            'me',
            m.id!,
            format: 'metadata',
            metadataHeaders: ['From', 'Subject', 'Date'],
          );
          String from = '', subject = '', date = '';
          for (final h in full.payload?.headers ?? []) {
            final name = (h.name ?? '').toLowerCase();
            if (name == 'from') from = (h.value ?? '').trim();
            if (name == 'subject') subject = (h.value ?? '').trim();
            if (name == 'date') date = (h.value ?? '').trim();
          }
          out.add(EmailMessage(
            id: m.id!,
            from: _shortFrom(from),
            subject: subject.isEmpty ? '(no subject)' : subject,
            snippet: (full.snippet ?? '').trim(),
            date: date,
          ));
        } catch (error, stack) {
          // Skip one bad message, keep others (honest partial results).
          developer.log('Gmail message fetch skipped',
              name: 'friday.gmail', error: error, stackTrace: stack, level: 800);
          continue;
        }
      }
      return out;
    });
  }

  static String _shortFrom(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return 'Unknown sender';
    // "John Doe <john@mail.com>" -> "John Doe", "<john@mail.com>" -> "john@mail.com"
    final angle = RegExp(r'<([^>]+)>').firstMatch(v);
    if (angle != null) {
      final name = v.substring(0, angle.start).trim().replaceAll('"', '');
      if (name.isNotEmpty) return name;
      return angle.group(1)!.trim();
    }
    if (v.length > 60) v = '${v.substring(0, 57).trim()}...';
    return v;
  }
}

/// Offline fake for tests / UI preview without Google setup.
class FakeGmailService implements GmailService {
  bool connected;
  final List<EmailMessage> messages;

  FakeGmailService({
    this.connected = false,
    this.messages = const [
      EmailMessage(
          id: '1',
          from: 'Boss',
          subject: 'Meeting at 4pm',
          snippet: 'Please join the review call'),
      EmailMessage(
          id: '2',
          from: 'Amazon',
          subject: 'Your OTP',
          snippet: 'Your code is 123456'),
    ],
  });

  @override
  Future<bool> isConnected() async => connected;

  @override
  Future<void> connect() async => connected = true;

  @override
  Future<void> disconnect() async => connected = false;

  @override
  Future<List<EmailMessage>> listUnread({int count = 5}) async {
    if (!connected) throw const GmailNotConnectedException();
    return messages.take(count.clamp(1, 10)).toList();
  }
}