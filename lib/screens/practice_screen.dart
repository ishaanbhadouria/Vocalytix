// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, undefined_prefixed_name

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:avaixa/models/session_models.dart';
import 'package:avaixa/services/local_session_store.dart';
import 'package:avaixa/widgets/avaixa_brand.dart';
import 'package:avaixa/widgets/session_trend_chart.dart';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;

class _WordSample {
  const _WordSample({
    required this.timestamp,
    required this.words,
  });

  final DateTime timestamp;
  final int words;
}

class _DetectedFiller {
  const _DetectedFiller({
    required this.label,
    required this.index,
  });

  final String label;
  final int index;
}

class _TranscriptChunk {
  const _TranscriptChunk({
    required this.text,
    required this.isWord,
  });

  final String text;
  final bool isWord;
}

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  static const String _cameraViewType = 'avaixa-camera-preview';
  static const String _cameraElementIdPrefix = 'avaixa-camera-element';
  static bool _cameraFactoryRegistered = false;
  static const String _replayViewType = 'avaixa-replay-video';
  static bool _replayFactoryRegistered = false;
  final LocalSessionStore _sessionStore = LocalSessionStore();

  int wordCount = 0;
  int fillerCount = 0;
  double wordsPerMinute = 0;
  String status = "Not Speaking";
  String transcript = "";
  double score = 100;
  String faceStatus = "Not tracking";
  double facePresencePct = 0;
  double eyeContactPct = 0;
  double headStabilityPct = 0;
  double gestureActivityPct = 0;
  int gestureFrames = 0;
  String visualMessage = "Start a session to get visual coaching feedback.";
  DateTime? startTime;
  bool isListening = false;
  bool cameraReady = false;
  String? _activeCameraElementId;
  CoachingMode selectedMode = CoachingMode.presentation;
  SessionOutcome selectedOutcome = SessionOutcome.unknown;
  final List<SessionLog> _sessionLogs = [];
  final List<SessionRecording> _sessionRecordings = [];
  final List<SessionReport> _sessionReports = [];
  SessionReport? _pendingReportDialog;
  int activeTabIndex = 0;
  bool hasSelectedMode = false;
  bool _homeLiveAudienceSelected = false;
  int tutorialPromptIndex = 0;
  DetailFilter selectedDetailFilter = DetailFilter.overview;
  int _lastProcessedWords = 0;
  final Set<String> _seenFillerKeys = {};
  List<FillerTimestamp> _currentFillerTimeline = [];
  html.VideoElement? _replayVideoElement;
  SessionRecording? _latestRecording;
  double _replayDurationSec = 0;
  double _replayPositionSec = 0;
  bool _replayPlaying = false;
  bool _replayListenersAttached = false;
  String? _pendingReplayUrl;
  bool _showReplayInMainCamera = false;
  bool _isScrubbingReplay = false;
  bool _resumeReplayAfterScrub = false;
  final List<_WordSample> _liveWordSamples = [];
  Timer? _paceRefreshTimer;
  Timer? _sessionTimer;
  Timer? _homeHintTimer;
  Timer? _contentFeedbackDebounce;
  int _lastLiveWordCount = 0;
  int _sessionElapsedSec = 0;
  double _lastSessionDurationSec = 0;
  bool _showLoadingOverlay = true;
  bool _isSessionBooting = false;
  int _hintIndex = 0;
  bool _showCameraReminder = true;
  DateTime? _lastTranscriptUpdateAt;
  List<double> _currentWordTimestampsSec = [];
  double _mockAudienceEnergy = 0.65;
  double _mockAudienceWarmth = 0.72;
  int _mockAudienceSize = 18;
  bool _liveAudienceImmersive = false;
  DateTime? _lastSpeechUiRefreshAt;
  DateTime? _lastFaceUiRefreshAt;
  int _lastSpeechUiWordCount = 0;
  int _contentFeedbackRequestId = 0;
  String _lastAiFeedbackTranscript = "";
  bool _contentFeedbackLoading = false;
  double _cachedContentScore = 0;
  List<String> _cachedContentFeedback = const [
    "Start speaking to generate content-level feedback.",
  ];

  static const Duration _speechUiRefreshInterval = Duration(milliseconds: 220);
  static const Duration _faceUiRefreshInterval = Duration(milliseconds: 180);
  static const Duration _contentFeedbackDebounceDelay =
      Duration(milliseconds: 900);

  static const String _cameraReminderStorageKey =
      'avaixa-hide-camera-reminder';

  static const List<String> _loadingHints = [
    "Look at the nose, not the eyes, for more natural eye contact.",
    "Pause silently instead of filling space with 'um' or 'like'.",
    "Lead with the point first, then support it with one example.",
    "Keep your chin level to look steadier on camera.",
  ];

  final Set<String> _singleWordFillers = const {
    "um",
    "uhm",
    "uh",
    "uhh",
    "uhhh",
    "so",
    "like",
    "thing",
  };

  @override
  void initState() {
    super.initState();
    _initCameraPreview();
    _initReplayPreview();
    _beginLoadingOverlay(const Duration(milliseconds: 2200));
    _restorePersistedSessionData();
    _showCameraReminder =
        html.window.localStorage[_cameraReminderStorageKey] != 'true';

    html.window.addEventListener("speech-update", (event) {
      final customEvent = event as html.CustomEvent;
      final transcript = customEvent.detail as String;
      if (transcript == this.transcript) return;

      final words = transcript.trim().isEmpty
          ? []
          : transcript.trim().split(RegExp(r"\s+"));

      final tokens = _tokenizeTranscript(transcript);
      final fillersDetected = _detectFillers(tokens);

      final seconds = startTime == null
          ? 0
          : DateTime.now().difference(startTime!).inSeconds;
      final now = DateTime.now();
      _updateWordTimestamps(words.length, now);
      final deltaWords = (words.length - _lastLiveWordCount).clamp(0, 60);
      _lastLiveWordCount = words.length;
      if (deltaWords > 0) {
        _liveWordSamples.add(_WordSample(timestamp: now, words: deltaWords));
      }
      _trimWordSamples(now);
      final liveWpm = _computeLiveWpm(now);
      final shouldRefreshUi = _shouldRefreshSpeechUi(now, words.length);

      this.transcript = transcript;
      wordCount = words.length;
      fillerCount = fillersDetected.length;
      status = "Speaking";
      wordsPerMinute = liveWpm > 0
          ? liveWpm
          : (seconds > 0 ? (wordCount / seconds) * 60 : 0);
      _updateFillerTimeline(transcript);
      if (shouldRefreshUi) {
        _refreshCachedContentAnalysis();
        setState(() {
          score = _calculateScore();
          _lastSpeechUiRefreshAt = now;
        });
      }
    });

    html.window.addEventListener("speech-stopped", (_) {
      setState(() {
        status = "Stopped";
        isListening = false;
      });
    });

    html.window.addEventListener("face-update", (event) {
      final customEvent = event as html.CustomEvent;
      final detail = customEvent.detail;
      if (detail is! String || detail.isEmpty) return;

      final payload = jsonDecode(detail) as Map<String, dynamic>;
      final now = DateTime.now();
      facePresencePct = _num(payload["facePresencePct"]);
      eyeContactPct = _num(payload["eyeContactPct"]);
      headStabilityPct = _num(payload["headStabilityPct"]);
      gestureActivityPct = _num(payload["gestureActivityPct"]);
      gestureFrames = (_num(payload["gestureFrames"])).round();
      final hasFace = payload["faceDetected"] == true;
      faceStatus = hasFace ? "Face Detected" : "Face Missing";
      visualMessage = _buildVisualMessage();

      final shouldRefreshUi = _isSessionBooting ||
          _lastFaceUiRefreshAt == null ||
          now.difference(_lastFaceUiRefreshAt!) >= _faceUiRefreshInterval;
      if (!shouldRefreshUi) return;

      setState(() {
        score = _calculateScore();
        _lastFaceUiRefreshAt = now;
        if (_isSessionBooting) {
          _isSessionBooting = false;
          _showLoadingOverlay = false;
        }
      });
    });

    html.window.addEventListener("face-error", (event) {
      final customEvent = event as html.CustomEvent;
      final detail = customEvent.detail?.toString() ?? "Face tracking failed.";
      setState(() {
        faceStatus = "Error";
        visualMessage = detail;
      });
    });

    html.window.addEventListener("recording-ready", (event) {
      final customEvent = event as html.CustomEvent;
      final detail = customEvent.detail;
      if (detail is! String || detail.isEmpty) return;
      final payload = jsonDecode(detail) as Map<String, dynamic>;
      final url = payload["url"]?.toString();
      if (url == null || url.isEmpty) return;
      final jsDuration = _num(payload["durationSec"]);

      setState(() {
        _sessionRecordings.insert(
          0,
          SessionRecording(
            url: url,
            mode: _pendingReportDialog?.mode ?? selectedMode,
            score: _pendingReportDialog?.overallScore ?? score,
            createdAt: DateTime.now(),
            transcript: transcript,
            wordTimestampsSec: List<double>.from(_currentWordTimestampsSec),
            fillerTimeline: List<FillerTimestamp>.from(
              _pendingReportDialog?.fillerTimeline ?? _currentFillerTimeline,
            ),
          ),
        );
        _latestRecording = _sessionRecordings.first;
        activeTabIndex = 0;
        _showReplayInMainCamera = true;
        _replayPlaying = false;
        _replayPositionSec = 0;
        _replayDurationSec = 0;
        if (jsDuration > 0) {
          _replayDurationSec = jsDuration;
          _lastSessionDurationSec = jsDuration;
        }
      });

      _loadReplay(_latestRecording!.url);

      if (_pendingReportDialog != null) {
        final report = _pendingReportDialog!;
        _pendingReportDialog = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showFullReportDialog(report);
        });
      }
    });
  }

  Future<void> _restorePersistedSessionData() async {
    final persisted = await _sessionStore.load();
    if (!mounted) return;
    setState(() {
      _sessionLogs
        ..clear()
        ..addAll(persisted.logs);
      _sessionReports
        ..clear()
        ..addAll(persisted.reports);
    });
  }

  Future<void> _persistReports() {
    return _sessionStore.saveReports(_sessionReports);
  }

  Future<void> _persistLogs() {
    return _sessionStore.saveLogs(_sessionLogs);
  }

  void _initCameraPreview() {
    if (!_cameraFactoryRegistered) {
      ui_web.platformViewRegistry.registerViewFactory(_cameraViewType,
          (int viewId) {
        final video = html.VideoElement()
          ..id = '$_cameraElementIdPrefix-$viewId'
          ..autoplay = true
          ..muted = true
          ..controls = false
          ..style.width = "100%"
          ..style.height = "100%"
          ..style.objectFit = "contain"
          ..setAttribute("playsinline", "true");
        return video;
      });
      _cameraFactoryRegistered = true;
    }

    setState(() {
      cameraReady = true;
    });
  }

  void _initReplayPreview() {
    if (!_replayFactoryRegistered) {
      ui_web.platformViewRegistry.registerViewFactory(_replayViewType,
          (int viewId) {
        final video = html.VideoElement()
          ..autoplay = false
          ..muted = false
          ..controls = false
          ..style.width = "100%"
          ..style.height = "100%"
          ..style.objectFit = "contain"
          ..setAttribute("playsinline", "true");
        _replayVideoElement = video;
        return video;
      });
      _replayFactoryRegistered = true;
    }
  }

  void _beginLoadingOverlay(Duration duration) {
    _homeHintTimer?.cancel();
    setState(() {
      _showLoadingOverlay = true;
      _hintIndex = 0;
    });

    _homeHintTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() {
        _hintIndex = (_hintIndex + 1) % _loadingHints.length;
      });
    });

    Future<void>.delayed(duration, () {
      if (!mounted || _isSessionBooting) return;
      _homeHintTimer?.cancel();
      setState(() {
        _showLoadingOverlay = false;
      });
    });
  }

  void _updateWordTimestamps(int newWordCount, DateTime now) {
    if (startTime == null) return;
    if (newWordCount <= _currentWordTimestampsSec.length) {
      _lastTranscriptUpdateAt = now;
      return;
    }

    final previousCount = _currentWordTimestampsSec.length;
    final newWords = newWordCount - previousCount;
    final elapsedSec = now.difference(startTime!).inMilliseconds / 1000.0;
    final previousUpdateAt = _lastTranscriptUpdateAt;
    final previousSec = previousUpdateAt == null
        ? 0.0
        : previousUpdateAt.difference(startTime!).inMilliseconds / 1000.0;
    final startSec = previousCount == 0 ? 0.0 : previousSec;
    final span = (elapsedSec - startSec).clamp(0.0, 6.0);

    for (var i = 0; i < newWords; i++) {
      final ratio = newWords == 1 ? 1.0 : (i + 1) / newWords;
      final sec = (startSec + (span * ratio)).clamp(0.0, elapsedSec);
      _currentWordTimestampsSec.add(sec);
    }

    _lastTranscriptUpdateAt = now;
  }

  Future<void> _handleStartSpeaking() async {
    if (isListening) return;
    if (_showCameraReminder) {
      final shouldContinue = await _showCameraReminderDialog();
      if (!shouldContinue) return;
    }
    startSpeaking();
  }

  Future<bool> _showCameraReminderDialog() async {
    var dontShowAgain = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF111A33),
              title: const Text(
                "Before You Record",
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Make sure you can see your whole face and gestures in the camera frame :)",
                    style: TextStyle(color: Colors.white70, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  CheckboxListTile(
                    value: dontShowAgain,
                    onChanged: (value) {
                      setDialogState(() {
                        dontShowAgain = value ?? false;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: const Color(0xFFE86D1F),
                    title: const Text(
                      "Don't show this again",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE86D1F),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Start Recording"),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && dontShowAgain) {
      html.window.localStorage[_cameraReminderStorageKey] = 'true';
      setState(() {
        _showCameraReminder = false;
      });
    }

    return result ?? false;
  }

  void startSpeaking() {
    startTime = DateTime.now();
    setState(() {
      _isSessionBooting = true;
      _showLoadingOverlay = true;
      _showReplayInMainCamera = false;
      status = "Listening...";
      wordCount = 0;
      fillerCount = 0;
      wordsPerMinute = 0;
      transcript = "";
      score = 100;
      faceStatus = "Initializing...";
      facePresencePct = 0;
      eyeContactPct = 0;
      headStabilityPct = 0;
      gestureActivityPct = 0;
      gestureFrames = 0;
      visualMessage = "Center your face and keep natural movement.";
      isListening = true;
      _lastProcessedWords = 0;
      _seenFillerKeys.clear();
      _currentFillerTimeline = [];
      _lastLiveWordCount = 0;
      _liveWordSamples.clear();
      _sessionElapsedSec = 0;
      _currentWordTimestampsSec = [];
      _lastTranscriptUpdateAt = null;
      _lastSpeechUiRefreshAt = null;
      _lastFaceUiRefreshAt = null;
      _lastSpeechUiWordCount = 0;
      _contentFeedbackRequestId++;
      _lastAiFeedbackTranscript = "";
      _contentFeedbackLoading = false;
      _contentFeedbackDebounce?.cancel();
      _cachedContentScore = 0;
      _cachedContentFeedback = const [
        "Start speaking to generate content-level feedback.",
      ];
    });
    _beginLoadingOverlay(const Duration(milliseconds: 2600));
    _paceRefreshTimer?.cancel();
    _paceRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _refreshLivePace();
    });
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || startTime == null || !isListening) return;
      setState(() {
        _sessionElapsedSec = DateTime.now().difference(startTime!).inSeconds;
      });
    });
    js.context.callMethod("startSpeech");
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startVisualTrackingWithRetry();
    });
  }

  void _startVisualTrackingWithRetry([int attempt = 0]) {
    if (!mounted || !isListening) return;

    final id = _activeCameraElementId;
    if (id != null && html.document.getElementById(id) != null) {
      js.context.callMethod("startFaceTracking", [id]);
      js.context.callMethod("startSessionRecording", [id]);
      return;
    }

    if (attempt < 12) {
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        _startVisualTrackingWithRetry(attempt + 1);
      });
      return;
    }

    js.context.callMethod("startFaceTracking");
    js.context.callMethod("startSessionRecording");
  }

  void stopSpeaking() {
    SessionReport? latestReport;
    if (wordCount >= 8) {
      latestReport = _createSessionReport();
    }

    js.context.callMethod("stopSpeech");
    js.context.callMethod("stopFaceTracking");
    js.context.callMethod("stopSessionRecording");
    _paceRefreshTimer?.cancel();
    _paceRefreshTimer = null;
    _sessionTimer?.cancel();
    _sessionTimer = null;
    final elapsedAtStop = startTime == null
        ? _sessionElapsedSec
        : DateTime.now().difference(startTime!).inSeconds;
    setState(() {
      status = "Stopped";
      faceStatus = "Stopped";
      isListening = false;
      _sessionElapsedSec = elapsedAtStop;
      _lastSessionDurationSec = elapsedAtStop.toDouble();
      if (latestReport != null) {
        _sessionReports.insert(0, latestReport);
        _pendingReportDialog = latestReport;
      }
    });
    if (latestReport != null) {
      unawaited(_persistReports());
      unawaited(_upgradeReportWithAiContentFeedback(latestReport));
    }

    if (latestReport != null) {
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (!mounted || _pendingReportDialog == null) return;
        final fallbackReport = _pendingReportDialog!;
        _pendingReportDialog = null;
        _showFullReportDialog(fallbackReport);
      });
    }
  }

  void _trimWordSamples(DateTime now) {
    _liveWordSamples.removeWhere(
      (sample) => now.difference(sample.timestamp).inSeconds > 12,
    );
  }

  double _computeLiveWpm(DateTime now) {
    if (_liveWordSamples.isEmpty) return 0;
    final windowWords =
        _liveWordSamples.fold<int>(0, (sum, s) => sum + s.words);
    final earliest = _liveWordSamples.first.timestamp;
    final windowSec = now.difference(earliest).inMilliseconds / 1000.0;
    final effectiveSec = windowSec < 2.0 ? 2.0 : windowSec;
    return (windowWords / effectiveSec) * 60.0;
  }

  void _refreshLivePace() {
    if (!mounted || !isListening) return;
    final now = DateTime.now();
    _trimWordSamples(now);
    final liveWpm = _computeLiveWpm(now);
    setState(() {
      wordsPerMinute = liveWpm;
      score = _calculateScore();
    });
  }

  bool _shouldRefreshSpeechUi(DateTime now, int currentWordCount) {
    if (_lastSpeechUiRefreshAt == null) return true;
    if (now.difference(_lastSpeechUiRefreshAt!) >= _speechUiRefreshInterval) {
      return true;
    }
    return (currentWordCount - _lastSpeechUiWordCount).abs() >= 6;
  }

  void _refreshCachedContentAnalysis() {
    final contentAnalysis = _analyzeContentFeedback();
    _cachedContentScore = contentAnalysis.$1;
    _cachedContentFeedback = contentAnalysis.$2;
    _lastSpeechUiWordCount = wordCount;
    _scheduleAiContentRefresh(contentAnalysis);
  }

  void _scheduleAiContentRefresh((double, List<String>) localAnalysis) {
    final transcriptText = transcript.trim();
    if (transcriptText.isEmpty) return;
    if (_countTranscriptWords(transcriptText) < 25) return;
    if (_contentFeedbackLoading &&
        _lastAiFeedbackTranscript == transcriptText) {
      return;
    }

    _contentFeedbackDebounce?.cancel();
    _contentFeedbackDebounce =
        Timer(_contentFeedbackDebounceDelay, () {
      unawaited(
        _loadAiContentFeedbackForLiveTranscript(
          transcriptText: transcriptText,
          localAnalysis: localAnalysis,
        ),
      );
    });
  }

  Future<void> _loadAiContentFeedbackForLiveTranscript({
    required String transcriptText,
    required (double, List<String>) localAnalysis,
  }) async {
    final requestId = ++_contentFeedbackRequestId;
    _contentFeedbackLoading = true;

    final aiAnalysis = await _requestAiContentFeedback(
      transcriptText: transcriptText,
      localAnalysis: localAnalysis,
    );

    if (!mounted || requestId != _contentFeedbackRequestId) return;

    _contentFeedbackLoading = false;
    if (aiAnalysis == null || transcript.trim() != transcriptText) return;

    setState(() {
      _lastAiFeedbackTranscript = transcriptText;
      _cachedContentScore = aiAnalysis.$1;
      _cachedContentFeedback = aiAnalysis.$2;
      _lastSpeechUiRefreshAt = DateTime.now();
    });
  }

  Future<(double, List<String>)?> _requestAiContentFeedback({
    required String transcriptText,
    required (double, List<String>) localAnalysis,
  }) async {
    try {
      final response = await html.HttpRequest.request(
        "/api/content-feedback",
        method: "POST",
        sendData: jsonEncode({
          "mode": selectedMode.name,
          "transcript": transcriptText,
          "delivery": {
            "wordCount": _countTranscriptWords(transcriptText),
            "wpm": wordsPerMinute,
            "fillerCount": fillerCount,
            "fillerRate":
                wordCount > 0 ? (fillerCount / wordCount) * 100 : 0.0,
            "confidenceScore": _currentConfidenceScore,
            "paceLabel": _paceLabel,
            "confidenceLabel": _confidenceLabel,
          },
          "localAnalysis": {
            "contentScore": localAnalysis.$1,
            "contentFeedback": localAnalysis.$2,
          },
          "recentReports": _recentReportsForMode(selectedMode, limit: 3)
              .map(
                (report) => {
                  "createdAt": report.createdAt.toIso8601String(),
                  "contentScore": report.contentScore,
                  "wordCount": report.wordCount,
                  "wpm": report.wpm,
                  "contentFeedback": report.contentFeedback,
                },
              )
              .toList(),
        }),
        requestHeaders: {
          "Content-Type": "application/json",
        },
      );

      final rawBody = response.responseText;
      if (rawBody == null || rawBody.isEmpty) return null;
      final parsed = jsonDecode(rawBody) as Map<String, dynamic>;
      final aiScore = (parsed["contentScore"] as num?)?.toDouble();
      final aiFeedback = (parsed["contentFeedback"] as List<dynamic>? ?? [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (aiScore == null || aiFeedback.isEmpty) return null;
      return (aiScore, aiFeedback.take(4).toList());
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _paceRefreshTimer?.cancel();
    _sessionTimer?.cancel();
    _homeHintTimer?.cancel();
    _contentFeedbackDebounce?.cancel();
    super.dispose();
  }

  SessionReport _createSessionReport() {
    final fillerRate = wordCount > 0 ? (fillerCount / wordCount) * 100 : 0.0;
    final contentAnalysis = _analyzeContentFeedback();
    final contentScore = contentAnalysis.$1;
    final contentFeedback = contentAnalysis.$2;
    final voiceFeedback = _buildCoachingFeedback(fillerRate);

    return SessionReport(
      mode: selectedMode,
      createdAt: DateTime.now(),
      overallScore: score,
      contentScore: contentScore,
      paceLabel: _paceLabel,
      confidenceLabel: _confidenceLabel,
      wordCount: wordCount,
      wpm: wordsPerMinute,
      fillerCount: fillerCount,
      fillerRate: fillerRate,
      confidenceScore: _currentConfidenceScore,
      facePresence: facePresencePct,
      eyeContact: eyeContactPct,
      headStability: headStabilityPct,
      gestureRating: _gestureActivityLabel,
      gestureMoments: gestureFrames,
      visualMessage: visualMessage,
      voiceFeedback: voiceFeedback,
      contentFeedback: contentFeedback,
      fillerTimeline: List<FillerTimestamp>.from(_currentFillerTimeline),
    );
  }

  Future<void> _upgradeReportWithAiContentFeedback(SessionReport report) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final transcriptText = transcript.trim();
    if (transcriptText.isEmpty) return;

    final localAnalysis = (report.contentScore, report.contentFeedback);
    final aiAnalysis = await _requestAiContentFeedback(
      transcriptText: transcriptText,
      localAnalysis: localAnalysis,
    );
    if (!mounted || aiAnalysis == null) return;

    final upgradedReport = SessionReport(
      mode: report.mode,
      createdAt: report.createdAt,
      overallScore: report.overallScore,
      contentScore: aiAnalysis.$1,
      paceLabel: report.paceLabel,
      confidenceLabel: report.confidenceLabel,
      wordCount: report.wordCount,
      wpm: report.wpm,
      fillerCount: report.fillerCount,
      fillerRate: report.fillerRate,
      confidenceScore: report.confidenceScore,
      facePresence: report.facePresence,
      eyeContact: report.eyeContact,
      headStability: report.headStability,
      gestureRating: report.gestureRating,
      gestureMoments: report.gestureMoments,
      visualMessage: report.visualMessage,
      voiceFeedback: report.voiceFeedback,
      contentFeedback: aiAnalysis.$2,
      fillerTimeline: report.fillerTimeline,
    );

    final index = _sessionReports.indexWhere(
      (item) =>
          item.createdAt == report.createdAt &&
          item.mode == report.mode &&
          item.wordCount == report.wordCount,
    );
    if (index == -1) return;

    setState(() {
      _sessionReports[index] = upgradedReport;
      if (_pendingReportDialog == report) {
        _pendingReportDialog = upgradedReport;
      }
    });
    await _persistReports();
  }

  Future<void> _showFullReportDialog(SessionReport report) async {
    final reportText = _buildReportText(report);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 760),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF141F3F), Color(0xFF0B1020)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.34),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF8A3D)
                                      .withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(0xFFFF8A3D)
                                        .withValues(alpha: 0.22),
                                  ),
                                ),
                                child: Text(
                                  _modeLabel(report.mode),
                                  style: const TextStyle(
                                    color: Color(0xFFFFC48B),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                "Session Report",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Generated ${report.createdAt.toLocal()}",
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.06),
                          ),
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildReportHero(report),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildReportMetricTile(
                          "Pace",
                          report.paceLabel,
                          "${report.wpm.toStringAsFixed(0)} WPM",
                          const Color(0xFF38BDF8),
                        ),
                        _buildReportMetricTile(
                          "Confidence",
                          report.confidenceLabel,
                          "${report.confidenceScore.toStringAsFixed(0)}/100",
                          const Color(0xFFFFB347),
                        ),
                        _buildReportMetricTile(
                          "Fillers",
                          report.fillerCount.toString(),
                          "${report.fillerRate.toStringAsFixed(1)}% rate",
                          const Color(0xFFEF4444),
                        ),
                        _buildReportMetricTile(
                          "Words",
                          report.wordCount.toString(),
                          "",
                          const Color(0xFF14B8A6),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 720;
                        final voiceCard = _buildReportSectionCard(
                          title: "Voice Coaching",
                          accent: const Color(0xFFFF8A3D),
                          icon: Icons.graphic_eq_rounded,
                          child: _buildReportFeedbackList(report.voiceFeedback),
                        );
                        final contentCard = _buildReportSectionCard(
                          title: "Content Coaching",
                          accent: const Color(0xFF38BDF8),
                          icon: Icons.edit_note_rounded,
                          child:
                              _buildReportFeedbackList(report.contentFeedback),
                        );
                        if (stacked) {
                          return Column(
                            children: [
                              voiceCard,
                              const SizedBox(height: 12),
                              contentCard,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: voiceCard),
                            const SizedBox(width: 12),
                            Expanded(child: contentCard),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 720;
                        final visualCard = _buildReportSectionCard(
                          title: "Visual Presence",
                          accent: const Color(0xFFFFB347),
                          icon: Icons.videocam_rounded,
                          child: Column(
                            children: [
                              _reportStatRow("Face Presence",
                                  "${report.facePresence.toStringAsFixed(1)}%"),
                              _reportStatRow("Eye Contact",
                                  "${report.eyeContact.toStringAsFixed(1)}%"),
                              _reportStatRow("Head Stability",
                                  "${report.headStability.toStringAsFixed(1)}%"),
                              _reportStatRow(
                                  "Gesture Rating", report.gestureRating),
                              _reportStatRow("Gesture Moments",
                                  report.gestureMoments.toString()),
                            ],
                          ),
                        );
                        final fillerCard = _buildReportSectionCard(
                          title: "Filler Timeline",
                          accent: const Color(0xFFEF4444),
                          icon: Icons.schedule_rounded,
                          child: _buildReportFillerTimeline(report),
                        );
                        if (stacked) {
                          return Column(
                            children: [
                              visualCard,
                              const SizedBox(height: 12),
                              fillerCard,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: visualCard),
                            const SizedBox(width: 12),
                            Expanded(child: fillerCard),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: reportText));
                          },
                          icon: const Icon(Icons.copy_all_rounded),
                          label: const Text("Copy Report"),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE86D1F),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("Close"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _buildReportText(SessionReport r) {
    final fillerTs = r.fillerTimeline.isEmpty
        ? "None detected"
        : r.fillerTimeline
            .take(20)
            .map((f) => "${_formatMinutesSeconds(f.seconds)} - ${f.word}")
            .join("\n");
    return """
Generated: ${r.createdAt.toLocal()}
Mode: ${_modeLabel(r.mode)}

OVERALL
- Overall Score: ${r.overallScore.toStringAsFixed(0)}/100
- Content Score: ${r.contentScore.toStringAsFixed(0)}/100

VOICE
- Pace: ${r.paceLabel}
- WPM: ${r.wpm.toStringAsFixed(1)}
- Words Spoken: ${r.wordCount}
- Filler Words: ${r.fillerCount}
- Filler Rate: ${r.fillerRate.toStringAsFixed(1)}%

VISUAL
- Confidence: ${r.confidenceLabel}
- Confidence Score: ${r.confidenceScore.toStringAsFixed(1)}/100
- Face Presence: ${r.facePresence.toStringAsFixed(1)}%
- Eye Contact: ${r.eyeContact.toStringAsFixed(1)}%
- Head Stability: ${r.headStability.toStringAsFixed(1)}%
- Gesture Rating: ${r.gestureRating}
- Gesture Moments: ${r.gestureMoments}
- Visual Note: ${r.visualMessage}

VOICE FEEDBACK
${r.voiceFeedback.map((e) => "- $e").join("\n")}

CONTENT FEEDBACK
${r.contentFeedback.map((e) => "- $e").join("\n")}

FILLER TIMESTAMPS
$fillerTs
""";
  }

  Widget _buildReportHero(SessionReport report) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8A3D), Color(0xFF203A73)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 620;
          final scoreColumn = Row(
            children: [
              _buildHeroScore(
                "Overall",
                report.overallScore.toStringAsFixed(0),
                "out of 100",
              ),
              const SizedBox(width: 14),
              _buildHeroScore(
                "Content",
                report.contentScore.toStringAsFixed(0),
                "content score",
              ),
            ],
          );
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Strongest takeaway",
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                report.contentFeedback.isNotEmpty
                    ? report.contentFeedback.first
                    : report.voiceFeedback.firstOrNull ??
                        "Keep refining your message and delivery together.",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                scoreColumn,
                const SizedBox(height: 16),
                summary,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: scoreColumn),
              const SizedBox(width: 18),
              Expanded(child: summary),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroScore(String label, String score, String caption) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              score,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportMetricTile(
      String label, String value, String subtitle, Color accent) {
    final hasSubtitle = subtitle.trim().isNotEmpty;
    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E172F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (hasSubtitle) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportSectionCard({
    required String title,
    required Color accent,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0E172F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildReportFeedbackList(List<String> items) {
    if (items.isEmpty) {
      return const Text(
        "No feedback available yet.",
        style: TextStyle(color: Colors.white60),
      );
    }
    return Column(
      children: items
          .map(
            (item) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_rounded,
                        color: Color(0xFFFF8A3D), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Colors.white,
                        height: 1.42,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildReportFillerTimeline(SessionReport report) {
    if (report.fillerTimeline.isEmpty) {
      return const Text(
        "No filler timestamps detected in this session.",
        style: TextStyle(color: Colors.white60, height: 1.4),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: report.fillerTimeline
          .take(20)
          .map(
            (filler) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF25131A),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.2)),
              ),
              child: Text(
                "${_formatMinutesSeconds(filler.seconds)} • ${filler.word}",
                style: const TextStyle(
                  color: Color(0xFFFFD2D2),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _reportStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  void _updateFillerTimeline(String fullTranscript) {
    if (startTime == null) return;

    final words = _tokenizeTranscript(fullTranscript);
    final totalWords = words.length;
    if (totalWords <= 0) return;

    final elapsedSec =
        DateTime.now().difference(startTime!).inMilliseconds / 1000.0;
    final scanStart = _lastProcessedWords > 0
        ? (_lastProcessedWords - 2).clamp(0, totalWords)
        : 0;

    final detected = _detectFillers(words);
    for (final item in detected) {
      if (item.index < scanStart) continue;
      final key = "${item.label}@${item.index}";
      if (_seenFillerKeys.add(key)) {
        final sec = (elapsedSec * ((item.index + 1) / totalWords))
            .clamp(0.0, elapsedSec);
        _currentFillerTimeline.add(FillerTimestamp(
          word: item.label,
          seconds: sec,
          transcriptIndex: item.index,
        ));
      }
    }

    _lastProcessedWords = totalWords;
  }

  void _loadReplay(String url) {
    final video = _replayVideoElement;
    if (video == null) {
      _pendingReplayUrl = url;
      return;
    }
    _pendingReplayUrl = null;

    video.pause();
    video.src = url;
    video.load();
    setState(() {
      _replayPlaying = false;
      _replayPositionSec = 0;
    });

    if (!_replayListenersAttached) {
      video.onLoadedMetadata.listen((_) {
        final dur = video.duration;
        if (dur.isFinite && dur > 0) {
          setState(() {
            _replayDurationSec = dur.toDouble();
            _replayPositionSec = 0;
          });
        }
        video.currentTime = 0;
      });

      video.onTimeUpdate.listen((_) {
        if (_isScrubbingReplay) return;
        setState(() {
          _replayPositionSec = video.currentTime.toDouble();
        });
      });

      video.onPlay.listen((_) {
        setState(() => _replayPlaying = true);
      });

      video.onPause.listen((_) {
        setState(() => _replayPlaying = false);
      });
      video.onEnded.listen((_) {
        setState(() {
          _replayPlaying = false;
          _replayPositionSec = _effectiveReplayDurationSec;
        });
      });
      _replayListenersAttached = true;
    }
  }

  void _toggleReplay() {
    final video = _replayVideoElement;
    if (video == null) return;
    if (_replayPlaying) {
      setState(() {
        _replayPlaying = false;
      });
      video.pause();
    } else {
      if (_effectiveReplayDurationSec > 0 &&
          video.currentTime >= _effectiveReplayDurationSec) {
        video.currentTime = 0;
        setState(() {
          _replayPositionSec = 0;
        });
      }
      setState(() {
        _replayPlaying = true;
      });
      video.play();
    }
  }

  void _seekReplay(double seconds) {
    final video = _replayVideoElement;
    if (video == null) return;
    final maxDuration =
        _effectiveReplayDurationSec > 0 ? _effectiveReplayDurationSec : 1.0;
    video.currentTime = seconds.clamp(0, maxDuration).toDouble();
    setState(() {
      _replayPositionSec = video.currentTime.toDouble();
    });
  }

  void _selectRecordingForReplay(SessionRecording recording) {
    setState(() {
      _latestRecording = recording;
      _showReplayInMainCamera = true;
      _replayPlaying = false;
      _replayPositionSec = 0;
      _replayDurationSec = 0;
      activeTabIndex = 0;
    });
    _loadReplay(recording.url);
  }

  double _calculateScore() {
    final wpm = wordsPerMinute;
    final words = wordCount;
    final fillers = fillerCount;
    final paceTarget = _targetWpmRange;
    double paceScore;
    if (wpm <= 0 || words < 8) {
      paceScore = 70;
    } else if (wpm < paceTarget.$1 - 20) {
      paceScore = 72;
    } else if (wpm < paceTarget.$1) {
      paceScore = 84;
    } else if (wpm <= paceTarget.$2) {
      paceScore = 100;
    } else if (wpm <= paceTarget.$2 + 25) {
      paceScore = 82;
    } else {
      paceScore = 68;
    }

    final fillerRate = words > 0 ? fillers / words : 0.0;
    final fillerScore = (100 - (fillerRate * 220)).clamp(0, 100).toDouble();
    final confidenceScore = ((facePresencePct * 0.35) +
            (eyeContactPct * 0.45) +
            (headStabilityPct * 0.20))
        .clamp(0, 100)
        .toDouble();
    final weights = _modeWeights;
    return ((paceScore * weights.$1) +
            (fillerScore * weights.$2) +
            (confidenceScore * weights.$3))
        .clamp(0, 100);
  }

  (double, double) get _targetWpmRange {
    switch (selectedMode) {
      case CoachingMode.interview:
        return (120, 165);
      case CoachingMode.presentation:
        return (125, 170);
      case CoachingMode.speech:
        return (115, 160);
      case CoachingMode.informal:
        return (135, 185);
      case CoachingMode.formal:
        return (110, 155);
      case CoachingMode.tutorials:
        return (120, 165);
    }
  }

  (double, double, double) get _modeWeights {
    switch (selectedMode) {
      case CoachingMode.interview:
        return (0.30, 0.45, 0.25);
      case CoachingMode.presentation:
        return (0.30, 0.40, 0.30);
      case CoachingMode.speech:
        return (0.33, 0.35, 0.32);
      case CoachingMode.informal:
        return (0.30, 0.35, 0.35);
      case CoachingMode.formal:
        return (0.35, 0.40, 0.25);
      case CoachingMode.tutorials:
        return (0.33, 0.34, 0.33);
    }
  }

  String get _paceLabel {
    final paceTarget = _targetWpmRange;
    if (wordsPerMinute <= 0) return "Waiting";
    if (wordsPerMinute < paceTarget.$1) return "Too Slow";
    if (wordsPerMinute <= paceTarget.$2) return "Good Pace";
    if (wordsPerMinute <= paceTarget.$2 + 25) return "A Bit Fast";
    return "Too Fast";
  }

  String get _confidenceLabel {
    final confidenceScore = _currentConfidenceScore;
    if (confidenceScore >= 85) return "Strong";
    if (confidenceScore >= 70) return "Good";
    if (confidenceScore >= 55) return "Needs Work";
    return "Low";
  }

  String _buildVisualMessage() {
    if (faceStatus == "Face Missing") {
      return "Bring your face fully into frame and keep eye level centered.";
    }
    if (eyeContactPct < 60) {
      return "Eye contact is drifting. Look back to center more often.";
    }
    if (headStabilityPct < 55) {
      return "Your head movement is high. Stabilize for stronger presence.";
    }
    if (gestureActivityPct < 8) {
      return "Add slight natural movement to avoid looking too rigid.";
    }
    if (gestureActivityPct > 55) {
      return "Movement is very active. Use calmer, deliberate gestures.";
    }
    return "Visual delivery looks solid. ${_modeVisualPriority()}";
  }

  String get _gestureActivityLabel {
    if (gestureActivityPct < 12) return "Need More";
    if (gestureActivityPct <= 42) return "Good";
    return "Too Much";
  }

  List<String> _buildCoachingFeedback(double fillerRate) {
    final feedback = <String>[];
    feedback.add("${_modeLabel(selectedMode)} goal: ${_modeCoreGoal()}.");

    if (wordCount < 20) {
      feedback.add("Run a longer rep (30-60s) to get more reliable scoring.");
    }

    final paceTarget = _targetWpmRange;
    if (wordsPerMinute > paceTarget.$2 + 25) {
      feedback.add(
          "Slow down your pace. Target ${paceTarget.$1.toInt()}-${paceTarget.$2.toInt()} WPM for this mode.");
    } else if (wordsPerMinute > 0 && wordsPerMinute < paceTarget.$1) {
      feedback.add("Speed up slightly to maintain momentum and energy.");
    } else if (wordsPerMinute >= paceTarget.$1 &&
        wordsPerMinute <= paceTarget.$2) {
      feedback.add("Pacing is in a strong range. Keep this rhythm.");
    }

    if (fillerRate >= 7) {
      feedback.add(
          "Fillers are high. Pause silently instead of using filler words.");
    } else if (fillerRate <= 3 && wordCount >= 20) {
      feedback.add("Great verbal control. Fillers are low.");
    }

    if (eyeContactPct < 65) {
      feedback
          .add("Eye contact is inconsistent. Return to center every sentence.");
    }

    if (headStabilityPct < 60) {
      feedback.add("Reduce head movement. Keep your chin level for authority.");
    }

    if (_gestureActivityLabel == "Need More") {
      feedback.add("Add intentional hand gestures to reinforce key points.");
    } else if (_gestureActivityLabel == "Too Much") {
      feedback.add("Trim extra movement. Use fewer, clearer gestures.");
    } else {
      feedback.add("Gesture activity is balanced for public speaking.");
    }

    feedback.add(_modeSpecificCoachingLine());

    if (feedback.isEmpty) {
      feedback
          .add("Strong delivery baseline. Keep practicing for consistency.");
    }

    return feedback.take(4).toList();
  }

  List<String> _modeKeywords(CoachingMode mode) {
    switch (mode) {
      case CoachingMode.interview:
        return const [
          "experience",
          "team",
          "impact",
          "result",
          "challenge",
          "learned",
          "responsibility",
          "improved",
        ];
      case CoachingMode.presentation:
        return const [
          "problem",
          "solution",
          "evidence",
          "data",
          "insight",
          "recommendation",
          "takeaway",
        ];
      case CoachingMode.speech:
        return const [
          "story",
          "lesson",
          "value",
          "belief",
          "growth",
          "purpose",
          "message",
        ];
      case CoachingMode.informal:
        return const [
          "honestly",
          "personally",
          "for me",
          "simple",
          "real",
          "everyday",
        ];
      case CoachingMode.formal:
        return const [
          "objective",
          "recommendation",
          "priority",
          "risk",
          "outcome",
          "next steps",
          "timeline",
        ];
      case CoachingMode.tutorials:
        return const [
          "clear",
          "example",
          "structure",
          "result",
          "confidence",
          "audience",
        ];
    }
  }

  (double, List<String>) _analyzeContentFeedback() {
    return _analyzeContentFeedbackForTranscript(transcript);
  }

  (double, List<String>) _analyzeContentFeedbackForTranscript(
      String sourceTranscript) {
    final text = sourceTranscript.trim();
    if (text.isEmpty) {
      return (0, ["Start speaking to generate content-level feedback."]);
    }

    final lower = text.toLowerCase();
    final words =
        lower.split(RegExp(r"\s+")).where((w) => w.isNotEmpty).toList();
    final sentences = _splitSentences(text);
    final firstSentence = sentences.isEmpty ? "" : sentences.first;
    final lastSentence = sentences.isEmpty ? "" : sentences.last;
    final wordTotal = words.length;
    final audiencePronounHits =
        _countPhraseHits(lower, const [" you ", " your ", " we ", " us "]);
    final storySignalHits = _countPhraseHits(lower, const [
      "when i",
      "one day",
      "i remember",
      "at first",
      "then",
      "suddenly",
      "but",
      "however",
      "challenge",
      "problem",
      "struggle",
      "learned",
    ]);

    final lengthScore = wordTotal < 20
        ? 48.0
        : wordTotal < 40
            ? 64.0
            : wordTotal < 120
                ? 88.0
                : 78.0;

    final structureCues = [
      "first",
      "second",
      "third",
      "because",
      "for example",
      "therefore",
      "however",
      "finally",
      "in conclusion"
    ];
    int structureHits = 0;
    for (final cue in structureCues) {
      if (lower.contains(cue)) structureHits++;
    }
    final structureScore = (40 + (structureHits * 12)).clamp(0, 100).toDouble();

    final specificityCues = [
      "for example",
      "specifically",
      "result",
      "impact",
      "increased",
      "reduced",
      "improved",
      "percent",
      "deadline",
      "weeks",
      "months",
    ];
    int specificityHits = RegExp(r"\b\d+(\.\d+)?\b").allMatches(lower).length;
    for (final cue in specificityCues) {
      if (lower.contains(cue)) specificityHits++;
    }
    final specificityScore =
        (35 + (specificityHits * 10)).clamp(0, 100).toDouble();

    final keywords = _modeKeywords(selectedMode);
    int modeHits = 0;
    for (final keyword in keywords) {
      if (lower.contains(keyword)) modeHits++;
    }
    final modeFitScore =
        (45 + ((modeHits / keywords.length) * 55)).clamp(0, 100).toDouble();

    final openingScore = _strongOpeningScore(firstSentence);
    final audienceScore = _audienceFocusScore(lower, audiencePronounHits);
    final storyScore = (35 + (storySignalHits * 8) + (specificityHits * 4))
        .clamp(0, 100)
        .toDouble();
    final endingScore =
        _endingStrengthScore(firstSentence, lastSentence, lower);
    final conversationalScore = _conversationalScore(sentences, lower);

    final contentScore = ((lengthScore * 0.12) +
            (structureScore * 0.20) +
            (specificityScore * 0.16) +
            (modeFitScore * 0.16) +
            (openingScore * 0.14) +
            (audienceScore * 0.10) +
            (storyScore * 0.06) +
            (endingScore * 0.04) +
            (conversationalScore * 0.02))
        .clamp(0, 100)
        .toDouble();

    final feedback = <String>[];
    final openingNeedsWork = _hasWeakOpening(firstSentence);
    final hedgingHits = _countPhraseHits(lower, const [
      "i think",
      "i guess",
      "maybe",
      "kind of",
      "sort of",
      "probably",
      "i feel like",
    ]);
    final strongestSentence = _bestSentence(sentences);
    final longSentence = _firstLongSentence(sentences);
    final hasConclusion = _hasConclusionCue(lastSentence);
    final repetitionWord = _mostRepeatedMeaningfulWord(words);
    final hasAudienceValue = _answersAudienceQuestion(lower, firstSentence);
    final hasStoryConflict = storySignalHits >= 2;
    final hasCallToAction = _hasCallToAction(lastSentence);
    final firstLastLink = _hasCircularEnding(firstSentence, lastSentence);
    final recentModeReports = _recentReportsForMode(selectedMode, limit: 3);
    final recentAverageContent = recentModeReports.isEmpty
        ? null
        : recentModeReports
                .map((report) => report.contentScore)
                .reduce((a, b) => a + b) /
            recentModeReports.length;

    final trendFeedback = _contentTrendFeedback(
      contentScore: contentScore,
      recentAverageContent: recentAverageContent,
      recentReportCount: recentModeReports.length,
    );
    if (trendFeedback != null) {
      feedback.add(trendFeedback);
    }

    final recurringPattern = _recurringContentPatternFeedback(recentModeReports);
    if (recurringPattern != null) {
      feedback.add(recurringPattern);
    }

    if (openingNeedsWork && firstSentence.isNotEmpty) {
      feedback.add(
          'Your opening is soft: "${_clipQuote(firstSentence)}". Start with a stronger hook, clear point, or vivid moment so the audience leans in immediately.');
    } else if (firstSentence.isNotEmpty) {
      feedback.add(
          'Your opening gives direction quickly: "${_clipQuote(firstSentence)}". That is a stronger Toastmasters-style start than easing in too slowly.');
    }

    if (!hasAudienceValue) {
      feedback.add(
          "The speech needs the listener payoff earlier. In the first minute, make it clearer why this matters to the audience, not just to you.");
    } else if (audiencePronounHits < 2 &&
        selectedMode != CoachingMode.interview) {
      feedback.add(
          "Shift a little more from 'I' to 'you' or 'we' so the audience feels included instead of just listening to your story.");
    }

    if (specificityScore < 70) {
      final referenceSentence =
          strongestSentence.isNotEmpty ? strongestSentence : firstSentence;
      feedback.add(
          'You make a claim in "${_clipQuote(referenceSentence)}", but it needs one clearer example, image, or result to feel convincing.');
    } else if (!hasStoryConflict &&
        (selectedMode == CoachingMode.presentation ||
            selectedMode == CoachingMode.speech)) {
      feedback.add(
          "Toastmasters puts a lot of weight on story movement. Add a challenge, tension point, or turning moment so the audience has something to follow.");
    } else if (strongestSentence.isNotEmpty) {
      feedback.add(
          'The strongest part is "${_clipQuote(strongestSentence)}" because it sounds specific instead of vague.');
    }

    if (hedgingHits >= 2) {
      feedback.add(
          "You hedge too much with phrases like 'maybe' or 'I think'. Say the point more directly so you sound more certain.");
    } else if (longSentence.isNotEmpty) {
      feedback.add(
          'This sentence runs long: "${_clipQuote(longSentence)}". Split it into two shorter ideas so the listener can follow you more easily.');
    } else if (structureScore < 70) {
      feedback.add(
          "Your ideas are there, but the structure is loose. Give the audience a path they can follow: point, support, takeaway.");
    } else if (conversationalScore < 68) {
      feedback.add(
          "The content is decent, but it could sound more conversational. Use spoken phrasing that feels like you're talking with the audience, not reading at them.");
    }

    if (!hasConclusion && !hasCallToAction && lastSentence.isNotEmpty) {
      feedback.add(
          'The ending feels unfinished: "${_clipQuote(lastSentence)}". Land on a takeaway, a call to action, or a final image that people can remember.');
    } else if (firstLastLink) {
      feedback.add(
          "The close connects back to the beginning, which gives the speech a more complete and memorable shape.");
    } else if (repetitionWord != null) {
      feedback.add(
          "You lean on '$repetitionWord' a lot. Swap in more precise wording so the answer sounds sharper.");
    } else if (modeFitScore < 68) {
      feedback.add(
          "The answer would feel stronger if it used more ${_modeLabel(selectedMode).toLowerCase()}-specific language.");
    }

    final modePersonalFeedback = _modeSpecificContentFeedback(
      lower: lower,
      wordTotal: wordTotal,
      structureScore: structureScore,
      specificityScore: specificityScore,
      hasAudienceValue: hasAudienceValue,
      hasConclusion: hasConclusion,
      hasCallToAction: hasCallToAction,
      hasStoryConflict: hasStoryConflict,
      hedgingHits: hedgingHits,
    );
    if (modePersonalFeedback != null) {
      feedback.add(modePersonalFeedback);
    }

    if (selectedMode == CoachingMode.interview &&
        !(lower.contains("situation") ||
            lower.contains("task") ||
            lower.contains("action") ||
            lower.contains("result"))) {
      feedback.add(
          "For interview answers, you still need a clearer STAR shape: situation, action, and measurable result.");
    }

    if (selectedMode == CoachingMode.presentation &&
        !lower.contains("takeaway") &&
        !lower.contains("recommendation") &&
        !hasConclusion) {
      feedback.add(
          "For presentation mode, land the message with a takeaway or recommendation instead of stopping after explanation.");
    }

    final uniqueFeedback = <String>{};
    final orderedFeedback = <String>[];
    for (final item in feedback) {
      final normalized = item.trim();
      if (normalized.isEmpty) continue;
      if (uniqueFeedback.add(normalized)) {
        orderedFeedback.add(normalized);
      }
    }

    return (contentScore, orderedFeedback.take(4).toList());
  }

  List<SessionReport> _recentReportsForMode(CoachingMode mode, {int limit = 3}) {
    return _sessionReports
        .where((report) => report.mode == mode)
        .take(limit)
        .toList();
  }

  String? _contentTrendFeedback({
    required double contentScore,
    required double? recentAverageContent,
    required int recentReportCount,
  }) {
    if (recentAverageContent == null || recentReportCount == 0) return null;
    final delta = contentScore - recentAverageContent;
    final modeName = _modeLabel(selectedMode);
    if (delta >= 6) {
      return "Compared with your last $recentReportCount $modeName reps, this one is sharper on content. Keep leaning into what made this answer more specific and directed.";
    }
    if (delta <= -6) {
      return "Compared with your last $recentReportCount $modeName reps, this one is less focused. Go back to the tighter structure and clearer examples you have already shown you can deliver.";
    }
    return null;
  }

  String? _recurringContentPatternFeedback(List<SessionReport> reports) {
    if (reports.length < 2) return null;

    int openingHits = 0;
    int specificityHits = 0;
    int structureHits = 0;
    int audienceHits = 0;
    int endingHits = 0;

    for (final report in reports) {
      final joined = report.contentFeedback.join(" ").toLowerCase();
      if (joined.contains("opening")) openingHits++;
      if (joined.contains("example") ||
          joined.contains("specific") ||
          joined.contains("result") ||
          joined.contains("convincing")) {
        specificityHits++;
      }
      if (joined.contains("structure") ||
          joined.contains("path they can follow") ||
          joined.contains("star shape")) {
        structureHits++;
      }
      if (joined.contains("audience") || joined.contains("listener payoff")) {
        audienceHits++;
      }
      if (joined.contains("ending") ||
          joined.contains("takeaway") ||
          joined.contains("call to action")) {
        endingHits++;
      }
    }

    final patternCounts = <String, int>{
      "opening": openingHits,
      "specificity": specificityHits,
      "structure": structureHits,
      "audience": audienceHits,
      "ending": endingHits,
    };

    String? topPattern;
    var topCount = 0;
    patternCounts.forEach((pattern, count) {
      if (count > topCount) {
        topCount = count;
        topPattern = pattern;
      }
    });

    if (topPattern == null || topCount < 2) return null;

    switch (topPattern) {
      case "opening":
        return "Your recent reps keep easing in too slowly. Personalize this one by deciding on the first line before you start so you sound intentional immediately.";
      case "specificity":
        return "Your recent pattern is good ideas without enough proof. Personalize this rep around one concrete example, number, or result that only you can say.";
      case "structure":
        return "Your recent reps keep circling the point before landing it. Personalize the structure around a simple sequence you trust: point, support, takeaway.";
      case "audience":
        return "Your recent reps focus on what you did more than why the listener should care. Personalize this one by stating the audience payoff earlier than usual.";
      case "ending":
        return "Your recent reps tend to fade out instead of landing cleanly. Pick your final takeaway before you begin so the close feels deliberate.";
    }
    return null;
  }

  String? _modeSpecificContentFeedback({
    required String lower,
    required int wordTotal,
    required double structureScore,
    required double specificityScore,
    required bool hasAudienceValue,
    required bool hasConclusion,
    required bool hasCallToAction,
    required bool hasStoryConflict,
    required int hedgingHits,
  }) {
    switch (selectedMode) {
      case CoachingMode.interview:
        if (!lower.contains("result") &&
            !lower.contains("impact") &&
            !RegExp(r"\b\d+(\.\d+)?\b").hasMatch(lower)) {
          return "Make the answer sound more like your story, not a job description. End with what changed because of your action, ideally with a concrete result.";
        }
        if (structureScore < 72) {
          return "For interview mode, personalize the shape around your real sequence: what the situation was, what you chose to do, and what happened after.";
        }
        return null;
      case CoachingMode.presentation:
        if (!hasAudienceValue) {
          return "For presentation mode, personalize the message around the audience's decision. Make it obvious what they should understand, believe, or do next.";
        }
        if (!hasConclusion && !hasCallToAction) {
          return "Your presentation content would feel more executive-ready with a closing recommendation. Tell the room what the takeaway is, not just what the facts are.";
        }
        return null;
      case CoachingMode.speech:
        if (!hasStoryConflict) {
          return "For speech mode, personalize the message with a moment of tension or change. People remember the turn, not just the topic.";
        }
        if (!hasAudienceValue) {
          return "The story is personal, but the lesson still needs to travel. Make the audience payoff explicit so it feels bigger than your own experience.";
        }
        return null;
      case CoachingMode.informal:
        if (hedgingHits >= 2) {
          return "For informal mode, keep the warmth but trust your point more. You sound most like yourself when you say the idea directly instead of cushioning it.";
        }
        if (wordTotal > 140) {
          return "This sounds personable, but a little long-winded. Trim one side detail so the main point comes through faster and sounds more naturally you.";
        }
        return null;
      case CoachingMode.formal:
        if (hedgingHits >= 1) {
          return "For formal mode, remove softeners like 'maybe' or 'I think' unless uncertainty is the actual message. The content should sound decisive and deliberate.";
        }
        if (specificityScore < 70) {
          return "Formal answers feel strongest when they sound grounded. Add one concrete risk, metric, or next step so the recommendation feels credible.";
        }
        return null;
      case CoachingMode.tutorials:
        if (wordTotal < 35) {
          return "For tutorial reps, give yourself one clean teaching arc: setup, example, takeaway. Right now the answer ends before the lesson fully lands.";
        }
        if (structureScore < 70) {
          return "This is a good practice rep to slow down and label the steps out loud. Tutorials become more personal when your listener can follow your exact teaching order.";
        }
        return null;
    }
  }

  String _modeLabel(CoachingMode mode) {
    switch (mode) {
      case CoachingMode.interview:
        return "Interview";
      case CoachingMode.presentation:
        return "Presentation";
      case CoachingMode.speech:
        return "Speech";
      case CoachingMode.informal:
        return "Informal Audience";
      case CoachingMode.formal:
        return "Formal Audience";
      case CoachingMode.tutorials:
        return "Tutorials";
    }
  }

  String _modeCoreGoal() {
    switch (selectedMode) {
      case CoachingMode.interview:
        return "clear, concise answers with steady confidence";
      case CoachingMode.presentation:
        return "structured storytelling with audience clarity";
      case CoachingMode.speech:
        return "strong vocal presence and emotional pacing";
      case CoachingMode.informal:
        return "natural conversational energy without rambling";
      case CoachingMode.formal:
        return "precise professional tone with controlled delivery";
      case CoachingMode.tutorials:
        return "guided reps with clear pacing and structure";
    }
  }

  String _modeSpecificCoachingLine() {
    switch (selectedMode) {
      case CoachingMode.interview:
        return "Use 45-90 second answer blocks and lead with your direct answer first.";
      case CoachingMode.presentation:
        return "Anchor each section with one headline sentence before details.";
      case CoachingMode.speech:
        return "Use deliberate pauses after key lines to let points land.";
      case CoachingMode.informal:
        return "Keep flow warm and natural, but avoid overusing fillers.";
      case CoachingMode.formal:
        return "Prioritize precise wording and slower transitions between points.";
      case CoachingMode.tutorials:
        return "Use each tutorial prompt for a 45-90 second focused rep.";
    }
  }

  String _modeVisualPriority() {
    switch (selectedMode) {
      case CoachingMode.interview:
        return "For interview mode, keep eye contact steady and gestures minimal.";
      case CoachingMode.presentation:
        return "For presentation mode, use broader gestures on key points.";
      case CoachingMode.speech:
        return "For speech mode, combine stillness and emphasis for impact.";
      case CoachingMode.informal:
        return "For informal mode, keep gestures relaxed and conversational.";
      case CoachingMode.formal:
        return "For formal mode, keep posture upright and movement disciplined.";
      case CoachingMode.tutorials:
        return "For tutorial mode, focus on one speaking behavior per rep.";
    }
  }

  String _outcomeLabel(SessionOutcome outcome) {
    switch (outcome) {
      case SessionOutcome.offer:
        return "Offer / Success";
      case SessionOutcome.advanced:
        return "Advanced Stage";
      case SessionOutcome.rejected:
        return "Rejected";
      case SessionOutcome.unknown:
        return "Unknown";
    }
  }

  void _saveSessionOutcome() {
    if (wordCount < 8) return;
    setState(() {
      _sessionLogs.add(SessionLog(
        mode: selectedMode,
        score: score,
        outcome: selectedOutcome,
        timestamp: DateTime.now(),
      ));
    });
    unawaited(_persistLogs());
  }

  String _patternSummary() {
    final modeLogs = _sessionLogs.where((s) => s.mode == selectedMode).toList();
    if (modeLogs.isEmpty) {
      return "No outcome data yet for ${_modeLabel(selectedMode)} mode.";
    }
    final success = modeLogs
        .where((s) =>
            s.outcome == SessionOutcome.offer ||
            s.outcome == SessionOutcome.advanced)
        .length;
    final successRate = (success / modeLogs.length) * 100;
    final avgScore =
        modeLogs.map((e) => e.score).reduce((a, b) => a + b) / modeLogs.length;
    return "In ${_modeLabel(selectedMode)} mode: ${successRate.toStringAsFixed(0)}% positive outcomes across ${modeLogs.length} sessions, avg score ${avgScore.toStringAsFixed(1)}.";
  }

  double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? "") ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    if (!hasSelectedMode) {
      return _buildModeEntryScreen(context);
    }

    final fillerRate = wordCount > 0 ? (fillerCount / wordCount) * 100 : 0.0;
    final confidenceScore = _currentConfidenceScore;
    final cameraHeight =
        ((MediaQuery.of(context).size.height * 0.65).clamp(420.0, 760.0))
            .toDouble();
    final isNarrow = MediaQuery.of(context).size.width < 980;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 10,
        title: AvaixaBrandButton(
          compact: true,
          onTap: isListening
              ? null
              : () {
                  setState(() {
                    hasSelectedMode = false;
                    activeTabIndex = 0;
                    _showReplayInMainCamera = false;
                  });
                  _beginLoadingOverlay(const Duration(milliseconds: 1800));
                },
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0B1020), Color(0xFF141F3F)],
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${_modeLabel(selectedMode)} Analytics",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Keep the camera live while you review analytics and transcript feedback.",
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.72)),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _metricTile("Status", status, const Color(0xFFF97316)),
                      _metricTile(
                          "Score", _scoreDisplay, const Color(0xFFFB923C)),
                      _metricTile("Pace", _paceLabel, const Color(0xFF9333EA)),
                      _metricTile("Confidence", _confidenceLabel,
                          const Color(0xFFFFB347)),
                      _metricTile("WPM", wordsPerMinute.toStringAsFixed(1),
                          const Color(0xFF0EA5E9)),
                      _metricTile("Fillers", fillerCount.toString(),
                          const Color(0xFFDC2626)),
                      _metricTile("Timer", _formatClock(_sessionElapsedSec),
                          const Color(0xFF14B8A6)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      ChoiceChip(
                        selected: activeTabIndex == 0,
                        label: const Text("Practice"),
                        onSelected: (_) => setState(() => activeTabIndex = 0),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        selected: activeTabIndex == 1,
                        label: const Text("Tutorials"),
                        onSelected: (_) => setState(() => activeTabIndex = 1),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        selected: activeTabIndex == 2,
                        label: const Text("Reports"),
                        onSelected: (_) => setState(() => activeTabIndex = 2),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        selected: activeTabIndex == 3,
                        label: const Text("Live Audience"),
                        onSelected: (_) => setState(() => activeTabIndex = 3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (activeTabIndex == 0)
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: isListening
                              ? null
                              : () {
                                  setState(() {
                                    hasSelectedMode = false;
                                  });
                                  _beginLoadingOverlay(
                                      const Duration(milliseconds: 1800));
                                },
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: Text("Mode: ${_modeLabel(selectedMode)}"),
                        ),
                      ],
                    ),
                  if (activeTabIndex == 0) const SizedBox(height: 8),
                  if (activeTabIndex == 0)
                    Row(
                      children: [
                        const Text("Detail View",
                            style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 12),
                        DropdownButton<DetailFilter>(
                          value: selectedDetailFilter,
                          dropdownColor: const Color(0xFF111A33),
                          style: const TextStyle(color: Colors.white),
                          items: DetailFilter.values
                              .map((f) => DropdownMenuItem(
                                    value: f,
                                    child: Text(_detailFilterLabel(f)),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => selectedDetailFilter = value);
                          },
                        ),
                      ],
                    ),
                  if (activeTabIndex == 0) const SizedBox(height: 10),
                  if (activeTabIndex == 1) ...[
                    _buildTutorialsCard(),
                    const SizedBox(height: 16),
                    _buildTutorialFocusCard(),
                  ] else if (activeTabIndex == 2) ...[
                    _buildReportsTab(),
                  ] else if (activeTabIndex == 3) ...[
                    _buildLiveAudienceTab(),
                  ] else
                    ...[],
                  if (activeTabIndex == 0) ...[
                    isNarrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCameraCard(cameraHeight),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  flex: 2,
                                  child: _buildCameraCard(cameraHeight)),
                            ],
                          ),
                    const SizedBox(height: 16),
                    _buildTranscriptCard(fillerRate, confidenceScore),
                    const SizedBox(height: 16),
                    if (selectedDetailFilter == DetailFilter.overview)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Quick Summary",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16)),
                              SizedBox(height: 8),
                              Text(
                                "Use Detail View to open Gestures or Outcomes. Camera and transcript stay visible.",
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (selectedDetailFilter == DetailFilter.gestures ||
                        selectedDetailFilter == DetailFilter.all) ...[
                      const SizedBox(height: 16),
                      _buildGestureCard(fillerRate),
                    ],
                    if (selectedDetailFilter == DetailFilter.outcomes ||
                        selectedDetailFilter == DetailFilter.all) ...[
                      const SizedBox(height: 16),
                      _buildOutcomeCard(),
                    ],
                  ],
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: _showLoadingOverlay
                ? _buildLoadingOverlay()
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _metricTile(String label, String value, Color color) {
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF182447),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildCameraCard(double cameraHeight) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      _showReplayInMainCamera
                          ? "Session Replay"
                          : (_liveAudienceImmersive
                              ? "Live Audience View"
                              : "Live Camera"),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: isListening ? null : _handleStartSpeaking,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        icon: const Icon(Icons.fiber_manual_record_rounded,
                            size: 16),
                        label: const Text("Record"),
                      ),
                      OutlinedButton.icon(
                        onPressed: isListening ? stopSpeaking : null,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: isListening
                                ? const Color(0xFFFFA24C)
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        icon: const _HexStopIcon(),
                        label: const Text("Stop"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: cameraHeight,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.black,
                  child: _showReplayInMainCamera
                      ? HtmlElementView(
                          key: ValueKey(
                              'avaixa-replay-main-${_latestRecording?.createdAt.millisecondsSinceEpoch ?? 0}'),
                          viewType: _replayViewType,
                          onPlatformViewCreated: (_) {
                            final url =
                                _latestRecording?.url ?? _pendingReplayUrl;
                            if (url != null && url.isNotEmpty) {
                              _loadReplay(url);
                            }
                          },
                        )
                      : (_liveAudienceImmersive
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                if (cameraReady)
                                  IgnorePointer(
                                    child: Opacity(
                                      opacity: 0.01,
                                      child: HtmlElementView(
                                        key: const ValueKey(
                                            'avaixa-camera-view-hidden'),
                                        viewType: _cameraViewType,
                                        onPlatformViewCreated: (viewId) {
                                          _activeCameraElementId =
                                              '$_cameraElementIdPrefix-$viewId';
                                        },
                                      ),
                                    ),
                                  )
                                else
                                  const Center(
                                      child: CircularProgressIndicator()),
                                _buildAudienceStage(
                                  stageHeight: cameraHeight,
                                  immersive: true,
                                ),
                              ],
                            )
                          : (cameraReady
                              ? HtmlElementView(
                                  key: const ValueKey('avaixa-camera-view'),
                                  viewType: _cameraViewType,
                                  onPlatformViewCreated: (viewId) {
                                    _activeCameraElementId =
                                        '$_cameraElementIdPrefix-$viewId';
                                  },
                                )
                              : const Center(
                                  child: CircularProgressIndicator()))),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0E172F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFFF8A3D).withValues(alpha: 0.32)),
              ),
              child: Text(
                _liveAudienceImmersive && !_showReplayInMainCamera
                    ? "You're looking at the mock audience while Avaixa still records and scores your delivery in the background."
                    : isListening
                        ? "Analytics stay live while recording. Keep speaking naturally and glance near the lens."
                        : "Start a session to record, score, and review replay without leaving this view.",
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            if (_showReplayInMainCamera && _latestRecording != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    onPressed: _toggleReplay,
                    icon: Icon(
                      _replayPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                      size: 30,
                      color: const Color(0xFF38BDF8),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _replayPositionSec
                          .clamp(
                            0,
                            _effectiveReplayDurationSec > 0
                                ? _effectiveReplayDurationSec
                                : 1.0,
                          )
                          .toDouble(),
                      min: 0,
                      max: _effectiveReplayDurationSec > 0
                          ? _effectiveReplayDurationSec
                          : 1.0,
                      onChangeStart: (_) {
                        _resumeReplayAfterScrub = _replayPlaying;
                        if (_replayPlaying) {
                          _replayVideoElement?.pause();
                        }
                        setState(() {
                          _isScrubbingReplay = true;
                        });
                      },
                      onChanged: (value) {
                        setState(() {
                          _replayPositionSec = value;
                        });
                      },
                      onChangeEnd: (value) {
                        _seekReplay(value);
                        final shouldResume = _resumeReplayAfterScrub;
                        setState(() {
                          _isScrubbingReplay = false;
                          _resumeReplayAfterScrub = false;
                        });
                        if (shouldResume) {
                          _replayVideoElement?.play();
                        }
                      },
                    ),
                  ),
                  Text(
                    "${_formatMinutesSeconds(_replayPositionSec)} / ${_formatMinutesSeconds(_effectiveReplayDurationSec)}",
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                "Filler Timestamps",
                style: TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (_latestRecording!.fillerTimeline.isEmpty)
                const Text(
                  "No filler words detected in this session.",
                  style: TextStyle(color: Colors.white70),
                ),
              if (_latestRecording!.fillerTimeline.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _latestRecording!.fillerTimeline.take(24).map((f) {
                    return ActionChip(
                      backgroundColor:
                          const Color(0xFF1D4ED8).withValues(alpha: 0.25),
                      side: const BorderSide(color: Color(0xFF1D4ED8)),
                      label: Text(
                        "${_formatMinutesSeconds(f.seconds)} • ${f.word}",
                        style: const TextStyle(color: Colors.white),
                      ),
                      onPressed: () => _seekReplay(f.seconds),
                    );
                  }).toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGestureCard(double fillerRate) {
    final coachingFeedback = _buildCoachingFeedback(fillerRate);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Gesture Feedback",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2B180B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFFF8A3D).withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Most Important Right Now",
                    style: TextStyle(
                      color: Color(0xFFFFC48B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    coachingFeedback.first,
                    style: const TextStyle(color: Colors.white, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _feedbackRow("Face Status", faceStatus),
            _feedbackRow(
                "Face Presence", "${facePresencePct.toStringAsFixed(1)}%"),
            _feedbackRow("Eye Contact", "${eyeContactPct.toStringAsFixed(1)}%"),
            _feedbackRow(
                "Head Stability", "${headStabilityPct.toStringAsFixed(1)}%"),
            _feedbackRow("Gesture Rating", _gestureActivityLabel),
            _feedbackRow("Gesture Moments", gestureFrames.toString()),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0E172F),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.blueGrey.withValues(alpha: 0.45)),
              ),
              child: Text(
                visualMessage,
                style: const TextStyle(
                    fontStyle: FontStyle.italic, color: Colors.white70),
              ),
            ),
            const SizedBox(height: 12),
            const Text("Coaching Feedback",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 8),
            ...coachingFeedback.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child:
                          Icon(Icons.circle, size: 7, color: Color(0xFF38BDF8)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                            color: Colors.white70, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscriptCard(double fillerRate, double confidenceScore) {
    final showingReplayTranscript =
        _showReplayInMainCamera && _latestRecording != null;
    final transcriptText =
        showingReplayTranscript ? _latestRecording!.transcript : transcript;
    final contentAnalysis = showingReplayTranscript
        ? _analyzeContentFeedbackForTranscript(transcriptText)
        : (_cachedContentScore, _cachedContentFeedback);
    final transcriptTokens = _tokenizeTranscript(transcriptText);
    final transcriptFillers = _detectFillers(transcriptTokens);
    final transcriptWordCount = showingReplayTranscript
        ? _countTranscriptWords(transcriptText)
        : wordCount;
    final transcriptFillerRate = transcriptWordCount > 0
        ? (transcriptFillers.length / transcriptWordCount) * 100
        : 0.0;
    final transcriptConfidence = confidenceScore;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                showingReplayTranscript
                    ? "Replay Transcript"
                    : "Live Transcript",
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 8),
            Text(
              "Words: $transcriptWordCount  •  Filler Rate: ${transcriptFillerRate.toStringAsFixed(1)}%  •  Confidence: ${transcriptConfidence.toStringAsFixed(0)}/100",
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 150),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0E172F),
                border:
                    Border.all(color: Colors.blueGrey.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: transcriptText.isEmpty
                  ? const Text(
                      "Start speaking to see transcript...",
                      style: TextStyle(color: Colors.white, height: 1.4),
                    )
                  : SelectableText(
                      transcriptText,
                      style: const TextStyle(color: Colors.white, height: 1.4),
                    ),
            ),
            const SizedBox(height: 10),
            if (transcriptFillers.isEmpty)
              const Text(
                "Detected fillers in transcript: none",
                style: TextStyle(color: Colors.white60, fontSize: 12),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: transcriptFillers
                    .map((filler) => filler.label)
                    .toSet()
                    .take(10)
                    .map(
                      (label) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25131A),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color:
                                const Color(0xFFEF4444).withValues(alpha: 0.24),
                          ),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFFFFD2D2),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 14),
            Text(
              "Content Score: ${contentAnalysis.$1.toStringAsFixed(0)}/100",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text("Content Feedback",
                style: TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...contentAnalysis.$2.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child:
                          Icon(Icons.circle, size: 7, color: Color(0xFF22D3EE)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                            color: Colors.white70, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutcomeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Outcome Tracking (AI Training Data)",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 8),
            const Text(
              "After a real interview/speech, log the result so Avaixa can learn success patterns by mode.",
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            DropdownButton<SessionOutcome>(
              value: selectedOutcome,
              dropdownColor: const Color(0xFF111A33),
              style: const TextStyle(color: Colors.white),
              items: SessionOutcome.values
                  .map((o) => DropdownMenuItem(
                        value: o,
                        child: Text(_outcomeLabel(o)),
                      ))
                  .toList(),
              onChanged: (o) {
                if (o == null) return;
                setState(() => selectedOutcome = o);
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed:
                  (isListening || wordCount < 8) ? null : _saveSessionOutcome,
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text("Save Session Outcome"),
            ),
            const SizedBox(height: 10),
            Text(
              _patternSummary(),
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionReplayCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Saved Session Replays",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 8),
            if (_sessionRecordings.isEmpty)
              const Text(
                "No recordings yet. Start and stop a session to save one.",
                style: TextStyle(color: Colors.white70),
              ),
            ..._sessionRecordings.take(6).map(
                  (recording) => Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E172F),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${_modeLabel(recording.mode)} • Score ${recording.score.toStringAsFixed(0)}",
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          recording.createdAt.toLocal().toString(),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _selectRecordingForReplay(recording),
                                icon:
                                    const Icon(Icons.play_circle_fill_rounded),
                                label: const Text("Load Replay"),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  html.window.open(recording.url, "_blank");
                                },
                                icon: const Icon(Icons.open_in_new_rounded),
                                label: const Text("Open File"),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text("Filler Timestamps",
                            style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        if (recording.fillerTimeline.isEmpty)
                          const Text("No filler words detected.",
                              style: TextStyle(color: Colors.white70)),
                        ...recording.fillerTimeline.take(10).map(
                              (f) => Text(
                                "${_formatMinutesSeconds(f.seconds)} - ${f.word}",
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullReportsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Full Reports",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 8),
            if (_sessionReports.isEmpty)
              const Text(
                "No reports yet. Stop a session after speaking to generate one.",
                style: TextStyle(color: Colors.white70),
              ),
            if (_sessionReports.length >= 3) ...[
              const SizedBox(height: 10),
              SessionTrendChart(
                scores: _sessionReports
                    .take(6)
                    .toList()
                    .reversed
                    .map((report) => report.overallScore)
                    .toList(),
                accentColor: const Color(0xFFFF8A3D),
                label: "Overall Score Trend",
              ),
              const SizedBox(height: 12),
              SessionTrendChart(
                scores: _sessionReports
                    .take(6)
                    .toList()
                    .reversed
                    .map((report) => report.confidenceScore)
                    .toList(),
                accentColor: const Color(0xFF38BDF8),
                label: "Confidence Trend",
              ),
            ],
            ..._sessionReports.take(8).map(
                  (report) => Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E172F),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${_modeLabel(report.mode)} • ${report.overallScore.toStringAsFixed(0)}/100",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                report.createdAt.toLocal().toString(),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _showFullReportDialog(report),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text("View"),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSessionReplayCard(),
        const SizedBox(height: 16),
        _buildFullReportsCard(),
      ],
    );
  }

  Widget _buildModeEntryScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 10,
        title: AvaixaBrandButton(
          compact: true,
          onTap: () {},
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1020), Color(0xFF141F3F)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Select Your Speaking Context",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                "The design stays intact. Pick a mode and Avaixa will tune scoring and coaching around it.",
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount =
                        width >= 1200 ? 3 : (width >= 760 ? 2 : 1);
                    final childAspectRatio = crossAxisCount == 3 ? 2.35 : 2.1;

                    final homeCards = <Widget>[
                      ...CoachingMode.values.map((mode) {
                        final selected =
                            !_homeLiveAudienceSelected && selectedMode == mode;
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            setState(() {
                              _homeLiveAudienceSelected = false;
                              selectedMode = mode;
                            });
                          },
                          onDoubleTap: () {
                            setState(() {
                              _homeLiveAudienceSelected = false;
                              selectedMode = mode;
                              hasSelectedMode = true;
                              _liveAudienceImmersive = false;
                              activeTabIndex =
                                  selectedMode == CoachingMode.tutorials
                                      ? 1
                                      : 0;
                              score = _calculateScore();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF4A230C)
                                  : const Color(0xFF182447),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFFFF8A3D)
                                    : Colors.white12,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _modeLabel(mode),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _modeDescription(mode),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                if (selected) ...[
                                  const SizedBox(height: 10),
                                  const Text(
                                    "Double-click to jump straight in.",
                                    style: TextStyle(
                                      color: Color(0xFFFFC48B),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          setState(() {
                            _homeLiveAudienceSelected = true;
                            selectedMode = CoachingMode.presentation;
                          });
                        },
                        onDoubleTap: () {
                          setState(() {
                            _homeLiveAudienceSelected = true;
                            selectedMode = CoachingMode.presentation;
                            hasSelectedMode = true;
                            _liveAudienceImmersive = false;
                            activeTabIndex = 3;
                            score = _calculateScore();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _homeLiveAudienceSelected
                                ? const Color(0xFF4A230C)
                                : const Color(0xFF182447),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _homeLiveAudienceSelected
                                  ? const Color(0xFFFF8A3D)
                                  : Colors.white12,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Live Audience",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Practice in front of a mock crowd with adjustable room size and energy.",
                                style: TextStyle(color: Colors.white70),
                              ),
                              if (_homeLiveAudienceSelected) ...[
                                const SizedBox(height: 10),
                                const Text(
                                  "Double-click to jump straight in.",
                                  style: TextStyle(
                                    color: Color(0xFFFFC48B),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ];

                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: childAspectRatio,
                      physics: const ClampingScrollPhysics(),
                      children: homeCards,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      hasSelectedMode = true;
                      _liveAudienceImmersive = false;
                      activeTabIndex = _homeLiveAudienceSelected
                          ? 3
                          : (selectedMode == CoachingMode.tutorials ? 1 : 0);
                      score = _calculateScore();
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE86D1F),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text("Start Mode"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _modeDescription(CoachingMode mode) {
    switch (mode) {
      case CoachingMode.interview:
        return "Clear, concise responses with strong confidence control.";
      case CoachingMode.presentation:
        return "Audience-facing delivery with balanced pace and gesture.";
      case CoachingMode.speech:
        return "Storytelling flow, vocal dynamics, and stage presence.";
      case CoachingMode.informal:
        return "Conversational style with relaxed but clear communication.";
      case CoachingMode.formal:
        return "Professional tone, precision, and disciplined delivery.";
      case CoachingMode.tutorials:
        return "Guided drills and behavioral prompts.";
    }
  }

  String _detailFilterLabel(DetailFilter filter) {
    switch (filter) {
      case DetailFilter.overview:
        return "Overview";
      case DetailFilter.gestures:
        return "Gestures";
      case DetailFilter.outcomes:
        return "Outcomes";
      case DetailFilter.all:
        return "All Sections";
    }
  }

  void _openTutorialPractice() {
    setState(() {
      activeTabIndex = 0;
      hasSelectedMode = true;
      tutorialPromptIndex = 0;
      score = _calculateScore();
    });
  }

  List<String> _behavioralPromptsForMode(CoachingMode mode) {
    switch (mode) {
      case CoachingMode.interview:
        return const [
          "Tell me about yourself and your background.",
          "Why do you want to work for this company?",
          "Describe a time you handled a difficult teammate.",
          "Tell me about a failure and what you learned.",
          "Describe a time you led under pressure.",
          "Why should we hire you for this role?",
        ];
      case CoachingMode.presentation:
        return const [
          "Open with a one-line thesis and why it matters.",
          "Explain one complex idea for a non-expert audience.",
          "Present one challenge and your solution clearly.",
          "State your strongest supporting evidence in 60 seconds.",
          "Close with a clear, confident call to action.",
        ];
      case CoachingMode.speech:
        return const [
          "Tell a short story that shaped your perspective.",
          "Describe a moment you overcame a major challenge.",
          "Deliver one value you believe in with a real example.",
          "Give a 60-second motivational message.",
          "End with a memorable final line.",
        ];
      case CoachingMode.informal:
        return const [
          "Introduce yourself to a new group naturally.",
          "Explain what you do in simple everyday language.",
          "Tell a short story from your week with energy.",
          "Give advice to a friend on managing stress.",
          "Share one opinion and support it casually.",
        ];
      case CoachingMode.formal:
        return const [
          "Give a concise professional introduction.",
          "Present a recommendation to senior stakeholders.",
          "Explain a difficult decision with clear reasoning.",
          "Deliver a formal status update with next steps.",
          "Close with a precise summary and requested action.",
        ];
      case CoachingMode.tutorials:
        return const [
          "Give a 60-second answer with one clear example and one result.",
          "Explain one idea in three steps: point, example, takeaway.",
          "Answer with STAR format: Situation, Task, Action, Result.",
          "Deliver one concise opening, one body point, one strong close.",
          "Speak for 45 seconds while minimizing filler words.",
        ];
    }
  }

  String get _currentBehavioralPrompt {
    final prompts = _behavioralPromptsForMode(selectedMode);
    final idx = tutorialPromptIndex.clamp(0, prompts.length - 1);
    return prompts[idx];
  }

  void _nextBehavioralPrompt() {
    final prompts = _behavioralPromptsForMode(selectedMode);
    setState(() {
      tutorialPromptIndex = (tutorialPromptIndex + 1) % prompts.length;
    });
  }

  Widget _buildTutorialsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Guided Tutorials",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 10),
            const Text(
              "Mode-tailored behavioral practice prompt:",
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text("Behavioral Prompt",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0E172F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFFF8A3D).withValues(alpha: 0.5)),
              ),
              child: Text(
                _currentBehavioralPrompt,
                style: const TextStyle(color: Colors.white, height: 1.35),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _nextBehavioralPrompt,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text("Next Prompt"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openTutorialPractice,
                    icon: const Icon(Icons.mic_none_rounded),
                    label: const Text("Open Practice"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              "Quick Tip",
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _modeSpecificCoachingLine(),
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTutorialFocusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Tutorial Focus",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 10),
            const Text(
              "Tutorial mode is for planning the rep first. Open Practice when you're ready to see the camera and live analytics.",
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0E172F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFFF8A3D).withValues(alpha: 0.32)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Before you start",
                    style: TextStyle(
                      color: Color(0xFFFFC48B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "1. Read the prompt out loud once.\n2. Decide your opening line.\n3. Pick one example or result to mention.\n4. Then tap Open Practice.",
                    style: TextStyle(color: Colors.white70, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveAudienceTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Live Audience Simulator",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 8),
                const Text(
                  "Practice like you're in front of a room, not just a webcam. Tune the crowd and then jump into a live rep.",
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 780;
                    if (isCompact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildAudienceStage(),
                          const SizedBox(height: 16),
                          _buildAudienceControls(),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _buildAudienceStage()),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: _buildAudienceControls()),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("How To Use It",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 10),
                const Text(
                  "1. Set the audience size and reaction.\n2. Imagine you're answering to the room, not the screen.\n3. Hit Start Live Audience Rep to switch back into Practice with that speaking mindset.",
                  style: TextStyle(color: Colors.white70, height: 1.45),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      activeTabIndex = 0;
                      selectedMode = CoachingMode.presentation;
                      _liveAudienceImmersive = true;
                    });
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE86D1F),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.campaign_rounded),
                  label: const Text("Start Live Audience Rep"),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudienceStage(
      {double stageHeight = 260, bool immersive = false}) {
    final seatCount = _mockAudienceSize.clamp(1, 40);
    final stageCanvasHeight = immersive
        ? (stageHeight - 92).clamp(180.0, 640.0).toDouble()
        : stageHeight;
    final energyLabel = _mockAudienceEnergy > 0.75
        ? "High energy crowd"
        : _mockAudienceEnergy > 0.45
            ? "Attentive crowd"
            : "Tough room";
    final warmthLabel = _mockAudienceWarmth > 0.72
        ? "Supportive"
        : _mockAudienceWarmth > 0.45
            ? "Neutral"
            : "Skeptical";

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(immersive ? 20 : 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF10192F), Color(0xFF09111F)],
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFFFF8A3D).withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded, color: Color(0xFFFFB347)),
              const SizedBox(width: 8),
              Text(
                "$seatCount seat${seatCount == 1 ? '' : 's'} • $warmthLabel • $energyLabel",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (immersive) ...[
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    "Immersive View",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: immersive ? 20 : 16),
          Container(
            height: stageCanvasHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF13213D), Color(0xFF0A1220)],
              ),
            ),
            child: Stack(
              children: [
                const Positioned(
                  left: 28,
                  right: 28,
                  top: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(Icons.lightbulb_circle_rounded,
                          color: Color(0x55FFF3D4), size: 18),
                      Icon(Icons.lightbulb_circle_rounded,
                          color: Color(0x55FFF3D4), size: 18),
                      Icon(Icons.lightbulb_circle_rounded,
                          color: Color(0x55FFF3D4), size: 18),
                    ],
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 28,
                  child: Container(
                    height: 62,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF5A2D12), Color(0xFF8C4A20)],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        immersive ? "Audience In Front Of You" : "Stage",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  top: 54,
                  bottom: 100,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 14,
                    children: List.generate(seatCount, (index) {
                      final reaction = ((index % 5) / 4);
                      final audienceColor = Color.lerp(
                              const Color(0xFF3B82F6),
                              const Color(0xFFFF8A3D),
                              (_mockAudienceWarmth + reaction) / 2)!
                          .withValues(alpha: 0.95);
                      final glow =
                          ((_mockAudienceEnergy * 0.45) + (reaction * 0.18))
                              .clamp(0.14, 0.65);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: audienceColor,
                              boxShadow: [
                                BoxShadow(
                                  color: audienceColor.withValues(alpha: glow),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 24,
                            height: 16,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudienceControls() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E172F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Crowd Settings",
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          const SizedBox(height: 12),
          Text("Audience Size: $_mockAudienceSize",
              style: const TextStyle(color: Colors.white70)),
          Slider(
            value: _mockAudienceSize.toDouble(),
            min: 1,
            max: 40,
            divisions: 39,
            activeColor: const Color(0xFFE86D1F),
            label: _mockAudienceSize.toString(),
            onChanged: (value) {
              setState(() {
                _mockAudienceSize = value.round();
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            "Warmth: ${(_mockAudienceWarmth * 100).round()}%",
            style: const TextStyle(color: Colors.white70),
          ),
          Slider(
            value: _mockAudienceWarmth,
            min: 0.15,
            max: 1,
            activeColor: const Color(0xFFFFB347),
            onChanged: (value) {
              setState(() {
                _mockAudienceWarmth = value;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            "Energy: ${(_mockAudienceEnergy * 100).round()}%",
            style: const TextStyle(color: Colors.white70),
          ),
          Slider(
            value: _mockAudienceEnergy,
            min: 0.15,
            max: 1,
            activeColor: const Color(0xFF38BDF8),
            onChanged: (value) {
              setState(() {
                _mockAudienceEnergy = value;
              });
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _audiencePresetChip("Investor Pitch", 14, 0.48, 0.62),
              _audiencePresetChip("Lecture Hall", 28, 0.72, 0.58),
              _audiencePresetChip("Demo Day", 20, 0.84, 0.76),
            ],
          ),
        ],
      ),
    );
  }

  Widget _audiencePresetChip(
      String label, int size, double warmth, double energy) {
    return ActionChip(
      backgroundColor: const Color(0xFF182447),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      onPressed: () {
        setState(() {
          _mockAudienceSize = size;
          _mockAudienceWarmth = warmth;
          _mockAudienceEnergy = energy;
        });
      },
    );
  }

  Widget _feedbackRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  double get _effectiveReplayDurationSec {
    if (_replayDurationSec > 0) return _replayDurationSec;
    return _lastSessionDurationSec > 0 ? _lastSessionDurationSec : 0;
  }

  String _formatClock(int totalSec) {
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    final mm = min.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return "$mm:$ss";
  }

  String _formatMinutesSeconds(double totalSec) {
    final safe = totalSec.isFinite ? totalSec : 0.0;
    final rounded = safe < 0 ? 0 : safe.round();
    final min = rounded ~/ 60;
    final sec = rounded % 60;
    return "${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
  }

  List<String> _splitSentences(String text) {
    return text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList();
  }

  bool _hasWeakOpening(String sentence) {
    final lower = sentence.toLowerCase().trim();
    if (lower.isEmpty) return true;
    return lower.startsWith("so ") ||
        lower.startsWith("um") ||
        lower.startsWith("uh") ||
        lower.startsWith("i guess") ||
        lower.startsWith("maybe") ||
        lower.startsWith("today i'm going to") ||
        lower.startsWith("i want to talk about");
  }

  int _countPhraseHits(String text, List<String> phrases) {
    var hits = 0;
    for (final phrase in phrases) {
      hits += RegExp(RegExp.escape(phrase)).allMatches(text).length;
    }
    return hits;
  }

  String _bestSentence(List<String> sentences) {
    if (sentences.isEmpty) return "";
    var best = "";
    var bestScore = -1;

    for (final sentence in sentences) {
      final lower = sentence.toLowerCase();
      var score = 0;
      if (RegExp(r"\b\d+(\.\d+)?\b").hasMatch(lower)) score += 3;
      if (lower.contains("for example") || lower.contains("specifically")) {
        score += 2;
      }
      if (lower.contains("result") ||
          lower.contains("impact") ||
          lower.contains("improved") ||
          lower.contains("increased") ||
          lower.contains("reduced")) {
        score += 2;
      }
      if (sentence.split(RegExp(r"\s+")).length >= 8) score += 1;

      if (score > bestScore) {
        bestScore = score;
        best = sentence;
      }
    }

    return best;
  }

  String _firstLongSentence(List<String> sentences) {
    for (final sentence in sentences) {
      if (sentence.split(RegExp(r"\s+")).length >= 24) {
        return sentence;
      }
    }
    return "";
  }

  bool _hasConclusionCue(String sentence) {
    final lower = sentence.toLowerCase();
    return lower.contains("that's why") ||
        lower.contains("the takeaway") ||
        lower.contains("in summary") ||
        lower.contains("overall") ||
        lower.contains("so the result") ||
        lower.contains("for that reason") ||
        lower.contains("which is why");
  }

  bool _hasCallToAction(String sentence) {
    final lower = sentence.toLowerCase();
    return lower.contains("so i want you to") ||
        lower.contains("i encourage you to") ||
        lower.contains("take the next step") ||
        lower.contains("remember this") ||
        lower.contains("start by") ||
        lower.contains("sign up") ||
        lower.contains("try this");
  }

  bool _answersAudienceQuestion(String lower, String firstSentence) {
    final firstLower = firstSentence.toLowerCase();
    return firstLower.contains("you") ||
        firstLower.contains("your") ||
        firstLower.contains("we") ||
        firstLower.contains("us") ||
        lower.contains("this matters because") ||
        lower.contains("the reason this matters") ||
        lower.contains("for you") ||
        lower.contains("for all of us");
  }

  double _strongOpeningScore(String firstSentence) {
    final lower = firstSentence.toLowerCase().trim();
    if (lower.isEmpty) return 20;
    var score = 42.0;
    if (!_hasWeakOpening(firstSentence)) score += 22;
    if (lower.contains("?")) score += 10;
    if (RegExp(r"\b\d+(\.\d+)?\b").hasMatch(lower)) score += 12;
    if (lower.startsWith("imagine") ||
        lower.startsWith("what if") ||
        lower.startsWith("when i") ||
        lower.startsWith("a few years ago") ||
        lower.startsWith("let me tell you")) {
      score += 16;
    }
    return score.clamp(0, 100);
  }

  double _audienceFocusScore(String lower, int audiencePronounHits) {
    var score = 35.0 + (audiencePronounHits * 8);
    if (_answersAudienceQuestion(lower, lower)) score += 18;
    return score.clamp(0, 100);
  }

  double _endingStrengthScore(
      String firstSentence, String lastSentence, String lower) {
    var score = 34.0;
    if (_hasConclusionCue(lastSentence)) score += 28;
    if (_hasCallToAction(lastSentence)) score += 18;
    if (_hasCircularEnding(firstSentence, lastSentence)) score += 20;
    return score.clamp(0, 100);
  }

  bool _hasCircularEnding(String firstSentence, String lastSentence) {
    final firstWords = _tokenizeTranscript(firstSentence).toSet();
    final lastWords = _tokenizeTranscript(lastSentence).toSet();
    if (firstWords.isEmpty || lastWords.isEmpty) return false;
    final overlap = firstWords.intersection(lastWords)
      ..removeWhere((word) => word.length < 4);
    return overlap.isNotEmpty;
  }

  double _conversationalScore(List<String> sentences, String lower) {
    if (sentences.isEmpty) return 40;
    final avgLength = sentences
            .map((sentence) => sentence.split(RegExp(r"\s+")).length)
            .reduce((a, b) => a + b) /
        sentences.length;
    var score = avgLength <= 18 ? 76.0 : 58.0;
    if (lower.contains("?")) score += 8;
    if (lower.contains("you're") ||
        lower.contains("we're") ||
        lower.contains("it's") ||
        lower.contains("don't") ||
        lower.contains("let's")) {
      score += 8;
    }
    return score.clamp(0, 100);
  }

  String? _mostRepeatedMeaningfulWord(List<String> words) {
    final counts = <String, int>{};
    const ignore = {
      "the",
      "and",
      "that",
      "this",
      "with",
      "have",
      "from",
      "your",
      "just",
      "like",
      "really",
      "very",
      "about",
      "because",
      "they",
      "them",
      "then",
      "when",
      "what",
      "would",
      "could",
      "there",
      "their",
      "were",
      "been",
      "into",
      "also",
      "some",
      "more",
    };

    for (final raw in words) {
      final word = raw.replaceAll(RegExp(r"[^a-z0-9']"), "");
      if (word.length < 4 || ignore.contains(word)) continue;
      counts[word] = (counts[word] ?? 0) + 1;
    }

    String? bestWord;
    var bestCount = 0;
    counts.forEach((word, count) {
      if (count > bestCount) {
        bestCount = count;
        bestWord = word;
      }
    });

    if (bestCount < 4) return null;
    return bestWord;
  }

  String _clipQuote(String sentence) {
    final trimmed = sentence.trim();
    if (trimmed.length <= 110) return trimmed;
    return "${trimmed.substring(0, 107)}...";
  }

  String get _scoreDisplay {
    if (wordCount < 8) return "TBD / 100";
    return "${score.toStringAsFixed(0)} / 100";
  }

  double get _currentConfidenceScore {
    return ((facePresencePct * 0.35) +
            (eyeContactPct * 0.45) +
            (headStabilityPct * 0.20))
        .clamp(0, 100)
        .toDouble();
  }

  int _countTranscriptWords(String text) {
    return _transcriptChunks(text).where((chunk) => chunk.isWord).length;
  }

  List<_TranscriptChunk> _transcriptChunks(String text) {
    return RegExp(r'\s+|[^\s]+').allMatches(text).map((match) {
      final value = match.group(0) ?? "";
      final hasWord = RegExp(r"[A-Za-z0-9']").hasMatch(value);
      return _TranscriptChunk(text: value, isWord: hasWord);
    }).toList();
  }

  Widget _buildLoadingOverlay() {
    return Container(
      key: ValueKey("loading-$_hintIndex-$_isSessionBooting-$hasSelectedMode"),
      color: const Color(0xF20A0F1D),
      alignment: Alignment.center,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF10182F),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: const Color(0xFFFF8A3D).withValues(alpha: 0.38)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8A3D).withValues(alpha: 0.12),
                blurRadius: 36,
                spreadRadius: 8,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.95, end: 1),
                duration: const Duration(milliseconds: 650),
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: const AvaixaBrandButton(),
              ),
              const SizedBox(height: 22),
              const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3.2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A3D)),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _isSessionBooting
                    ? "Warming up your live coaching session..."
                    : "Loading Avaixa...",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _loadingHints[_hintIndex],
                  key: ValueKey(_hintIndex),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _tokenizeTranscript(String text) {
    final lower = text.toLowerCase();
    final cleaned = lower.replaceAll(RegExp(r"[^\w\s'-]"), " ");
    return cleaned.split(RegExp(r"\s+")).where((w) => w.isNotEmpty).toList();
  }

  List<_DetectedFiller> _detectFillers(List<String> words) {
    final results = <_DetectedFiller>[];
    int i = 0;
    while (i < words.length) {
      final word = words[i];
      final next = i + 1 < words.length ? words[i + 1] : "";

      if (word == "you" && next == "know") {
        results.add(_DetectedFiller(label: "you know", index: i));
        i += 2;
        continue;
      }

      if (word == "and" && next == "stuff") {
        results.add(_DetectedFiller(label: "and stuff", index: i));
        i += 2;
        continue;
      }

      if (_singleWordFillers.contains(word)) {
        if (word == "like") {
          if (_isLikeFiller(words, i)) {
            results.add(_DetectedFiller(label: "like", index: i));
          }
        } else if (word == "so") {
          if (_isSoFiller(words, i)) {
            results.add(_DetectedFiller(label: "so", index: i));
          }
        } else {
          results.add(_DetectedFiller(label: word, index: i));
        }
      }
      i += 1;
    }
    return results;
  }

  bool _isLikeFiller(List<String> words, int i) {
    final prev = i > 0 ? words[i - 1] : "";
    final next = i + 1 < words.length ? words[i + 1] : "";
    const lexicalBefore = {
      "would",
      "will",
      "could",
      "can",
      "should",
      "feel",
      "feels",
      "felt",
      "looks",
      "look",
      "sound",
      "sounds",
      "seem",
      "seems",
      "is",
      "are",
      "was",
      "were",
      "be",
      "been",
      "being"
    };
    const lexicalAfter = {
      "to",
      "a",
      "an",
      "the",
      "this",
      "that",
      "these",
      "those",
      "my",
      "your",
      "our",
      "their",
      "his",
      "her",
      "me",
      "him",
      "them",
    };

    if (lexicalBefore.contains(prev) || lexicalAfter.contains(next)) {
      return false;
    }
    return true;
  }

  bool _isSoFiller(List<String> words, int i) {
    if (i == 0) return true;
    final prev = words[i - 1];
    const fillerLikeBefore = {"um", "uh", "like", "you", "know"};
    return fillerLikeBefore.contains(prev);
  }
}

class _HexStopIcon extends StatelessWidget {
  const _HexStopIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.hexagon, size: 18, color: Color(0xFFFFA24C)),
          Icon(Icons.stop_rounded, size: 9, color: Color(0xFFFFF0E0)),
        ],
      ),
    );
  }
}
