// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, undefined_prefixed_name

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vocalytix/widgets/session_trend_chart.dart';
import 'package:vocalytix/widgets/vocalytix_brand.dart';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;

enum CoachingMode {
  interview,
  presentation,
  speech,
  informal,
  formal,
  tutorials
}

enum SessionOutcome { offer, advanced, rejected, unknown }

enum DetailFilter { overview, gestures, outcomes, all }

class FillerTimestamp {
  const FillerTimestamp({
    required this.word,
    required this.seconds,
  });

  final String word;
  final double seconds;
}

class SessionLog {
  const SessionLog({
    required this.mode,
    required this.score,
    required this.outcome,
    required this.timestamp,
  });

  final CoachingMode mode;
  final double score;
  final SessionOutcome outcome;
  final DateTime timestamp;
}

class SessionRecording {
  const SessionRecording({
    required this.url,
    required this.mode,
    required this.score,
    required this.createdAt,
    required this.fillerTimeline,
  });

  final String url;
  final CoachingMode mode;
  final double score;
  final DateTime createdAt;
  final List<FillerTimestamp> fillerTimeline;
}

class SessionReport {
  const SessionReport({
    required this.mode,
    required this.createdAt,
    required this.overallScore,
    required this.contentScore,
    required this.paceLabel,
    required this.confidenceLabel,
    required this.wordCount,
    required this.wpm,
    required this.fillerCount,
    required this.fillerRate,
    required this.confidenceScore,
    required this.facePresence,
    required this.eyeContact,
    required this.headStability,
    required this.gestureRating,
    required this.gestureMoments,
    required this.visualMessage,
    required this.voiceFeedback,
    required this.contentFeedback,
    required this.fillerTimeline,
  });

  final CoachingMode mode;
  final DateTime createdAt;
  final double overallScore;
  final double contentScore;
  final String paceLabel;
  final String confidenceLabel;
  final int wordCount;
  final double wpm;
  final int fillerCount;
  final double fillerRate;
  final double confidenceScore;
  final double facePresence;
  final double eyeContact;
  final double headStability;
  final String gestureRating;
  final int gestureMoments;
  final String visualMessage;
  final List<String> voiceFeedback;
  final List<String> contentFeedback;
  final List<FillerTimestamp> fillerTimeline;
}

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

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  static const String _cameraViewType = 'vocalytix-camera-preview';
  static const String _cameraElementIdPrefix = 'vocalytix-camera-element';
  static bool _cameraFactoryRegistered = false;
  static const String _replayViewType = 'vocalytix-replay-video';
  static bool _replayFactoryRegistered = false;

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
  final List<_WordSample> _liveWordSamples = [];
  Timer? _paceRefreshTimer;
  Timer? _sessionTimer;
  Timer? _homeHintTimer;
  int _lastLiveWordCount = 0;
  int _sessionElapsedSec = 0;
  double _lastSessionDurationSec = 0;
  bool _showLoadingOverlay = true;
  bool _isSessionBooting = false;
  int _hintIndex = 0;

  static const List<String> _loadingHints = [
    "Look at the nose, not the eyes, for more natural eye contact.",
    "Pause silently instead of filling space with 'um' or 'like'.",
    "Lead with the point first, then support it with one example.",
    "Keep your chin level to look steadier on camera.",
  ];

  final Set<String> _singleWordFillers = const {
    "um",
    "uh",
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

    html.window.addEventListener("speech-update", (event) {
      final customEvent = event as html.CustomEvent;
      final transcript = customEvent.detail as String;

      final words = transcript.trim().isEmpty
          ? []
          : transcript.trim().split(RegExp(r"\s+"));

      final tokens = _tokenizeTranscript(transcript);
      final fillersDetected = _detectFillers(tokens);

      final seconds = startTime == null
          ? 0
          : DateTime.now().difference(startTime!).inSeconds;
      final now = DateTime.now();
      final deltaWords = (words.length - _lastLiveWordCount).clamp(0, 60);
      _lastLiveWordCount = words.length;
      if (deltaWords > 0) {
        _liveWordSamples.add(_WordSample(timestamp: now, words: deltaWords));
      }
      _trimWordSamples(now);
      final liveWpm = _computeLiveWpm(now);

      setState(() {
        this.transcript = transcript;
        wordCount = words.length;
        fillerCount = fillersDetected.length;
        status = "Speaking";
        wordsPerMinute = liveWpm > 0
            ? liveWpm
            : (seconds > 0 ? (wordCount / seconds) * 60 : 0);
        score = _calculateScore();
      });

      _updateFillerTimeline(transcript);
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
      setState(() {
        facePresencePct = _num(payload["facePresencePct"]);
        eyeContactPct = _num(payload["eyeContactPct"]);
        headStabilityPct = _num(payload["headStabilityPct"]);
        gestureActivityPct = _num(payload["gestureActivityPct"]);
        gestureFrames = (_num(payload["gestureFrames"])).round();
        final hasFace = payload["faceDetected"] == true;
        faceStatus = hasFace ? "Face Detected" : "Face Missing";
        visualMessage = _buildVisualMessage();
        score = _calculateScore();
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
            fillerTimeline: List<FillerTimestamp>.from(
              _pendingReportDialog?.fillerTimeline ?? _currentFillerTimeline,
            ),
          ),
        );
        _latestRecording = _sessionRecordings.first;
        activeTabIndex = 0;
        _showReplayInMainCamera = true;
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

  @override
  void dispose() {
    _paceRefreshTimer?.cancel();
    _sessionTimer?.cancel();
    _homeHintTimer?.cancel();
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

  Future<void> _showFullReportDialog(SessionReport report) async {
    final reportText = _buildReportText(report);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111A33),
          title: Text(
            "Full Session Report • ${_modeLabel(report.mode)}",
            style: const TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: SelectableText(
                reportText,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: reportText));
              },
              child: const Text("Copy Report"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Close"),
            ),
          ],
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
        _currentFillerTimeline
            .add(FillerTimestamp(word: item.label, seconds: sec));
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

    video.src = url;
    video.load();

    if (!_replayListenersAttached) {
      video.onLoadedMetadata.listen((_) {
        final dur = video.duration;
        if (dur.isFinite && dur > 0) {
          setState(() {
            _replayDurationSec = dur.toDouble();
            _replayPositionSec = 0;
          });
        }
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
      _replayListenersAttached = true;
    }
  }

  void _toggleReplay() {
    final video = _replayVideoElement;
    if (video == null) return;
    if (_replayPlaying) {
      video.pause();
    } else {
      video.play();
    }
  }

  void _seekReplay(double seconds) {
    final video = _replayVideoElement;
    if (video == null) return;
    video.currentTime = seconds.clamp(0, _replayDurationSec).toDouble();
    setState(() {
      _replayPositionSec = video.currentTime.toDouble();
    });
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
    feedback.add(
        "You did a good job leaning into ${_modeLabel(selectedMode).toLowerCase()} mode.");

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

    final transcriptMoment = _highlightedTranscriptMoment;
    if (transcriptMoment != null) {
      feedback.add(
          'Strong moment: "$transcriptMoment" gives you something worth keeping.');
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
    final text = transcript.trim();
    if (text.isEmpty) {
      return (0, ["Start speaking to generate content-level feedback."]);
    }

    final lower = text.toLowerCase();
    final words =
        lower.split(RegExp(r"\s+")).where((w) => w.isNotEmpty).toList();
    final wordTotal = words.length;

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

    final contentScore = ((lengthScore * 0.20) +
            (structureScore * 0.30) +
            (specificityScore * 0.25) +
            (modeFitScore * 0.25))
        .clamp(0, 100)
        .toDouble();

    final feedback = <String>[];
    if (wordTotal < 30) {
      feedback.add(
          "Give longer responses (45-90 seconds) so your message feels complete.");
    } else {
      feedback.add("Response length is solid for analysis.");
    }

    final transcriptMoment = _highlightedTranscriptMoment;
    if (transcriptMoment != null) {
      feedback
          .add('You did a really good job when you said "$transcriptMoment".');
    }

    if (structureScore < 70) {
      feedback.add(
          "Add stronger structure: start with your point, then one example, then result.");
    } else {
      feedback.add("Your structure is clear and easy to follow.");
    }

    if (specificityScore < 70) {
      feedback.add(
          "Add concrete evidence: numbers, outcomes, or a specific scenario.");
    } else {
      feedback.add("Good specificity. You used concrete details well.");
    }

    if (modeFitScore < 68) {
      feedback.add(
          "Use more ${_modeLabel(selectedMode).toLowerCase()}-specific language for stronger alignment.");
    } else {
      feedback
          .add("Content aligns well with ${_modeLabel(selectedMode)} mode.");
    }

    if (selectedMode == CoachingMode.interview &&
        !(lower.contains("situation") ||
            lower.contains("task") ||
            lower.contains("action") ||
            lower.contains("result"))) {
      feedback.add(
          "For interview answers, use STAR flow: Situation, Task, Action, Result.");
    }

    return (contentScore, feedback.take(4).toList());
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
        title: VocalytixBrandButton(
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
                    _buildCameraCard((cameraHeight * 0.72).clamp(320.0, 620.0)),
                  ] else if (activeTabIndex == 2) ...[
                    _buildReportsTab(),
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
                          : "Live Camera",
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
                        onPressed: isListening ? null : startSpeaking,
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
                              'vocalytix-replay-main-${_latestRecording?.createdAt.millisecondsSinceEpoch ?? 0}'),
                          viewType: _replayViewType,
                          onPlatformViewCreated: (_) {
                            final url =
                                _latestRecording?.url ?? _pendingReplayUrl;
                            if (url != null && url.isNotEmpty) {
                              _loadReplay(url);
                            }
                          },
                        )
                      : (cameraReady
                          ? HtmlElementView(
                              key: const ValueKey('vocalytix-camera-view'),
                              viewType: _cameraViewType,
                              onPlatformViewCreated: (viewId) {
                                _activeCameraElementId =
                                    '$_cameraElementIdPrefix-$viewId';
                              },
                            )
                          : const Center(child: CircularProgressIndicator())),
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
                isListening
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
                        _isScrubbingReplay = true;
                      },
                      onChanged: (value) {
                        setState(() {
                          _replayPositionSec = value;
                        });
                      },
                      onChangeEnd: (value) {
                        _seekReplay(value);
                        _isScrubbingReplay = false;
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
    final contentAnalysis = _analyzeContentFeedback();
    final contentScore = contentAnalysis.$1;
    final contentFeedback = contentAnalysis.$2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Live Transcript",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 8),
            Text(
              "Words: $wordCount  •  Filler Rate: ${fillerRate.toStringAsFixed(1)}%  •  Confidence: ${confidenceScore.toStringAsFixed(0)}/100",
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (_highlightedTranscriptMoment != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B180B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFFF8A3D).withValues(alpha: 0.42)),
                ),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white70, height: 1.35),
                    children: [
                      const TextSpan(
                        text: "Highlighted moment: ",
                        style: TextStyle(
                          color: Color(0xFFFFC48B),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(text: _highlightedTranscriptMoment),
                    ],
                  ),
                ),
              ),
            ],
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
              child: SelectableText(
                transcript.isEmpty
                    ? "Start speaking to see transcript..."
                    : transcript,
                style: const TextStyle(color: Colors.white, height: 1.4),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              "Content Score: ${contentScore.toStringAsFixed(0)}/100",
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
            ...contentFeedback.map(
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
              "After a real interview/speech, log the result so Vocalytix can learn success patterns by mode.",
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
                        OutlinedButton.icon(
                          onPressed: () {
                            html.window.open(recording.url, "_blank");
                          },
                          icon: const Icon(Icons.play_circle_outline_rounded),
                          label: const Text("Open Recording"),
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
        title: VocalytixBrandButton(
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
                "The design stays intact. Pick a mode and Vocalytix will tune scoring and coaching around it.",
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

                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: childAspectRatio,
                      physics: const ClampingScrollPhysics(),
                      children: CoachingMode.values.map((mode) {
                        final selected = selectedMode == mode;
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            setState(() {
                              selectedMode = mode;
                            });
                          },
                          onDoubleTap: () {
                            setState(() {
                              selectedMode = mode;
                              hasSelectedMode = true;
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
                      }).toList(),
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
                      activeTabIndex =
                          selectedMode == CoachingMode.tutorials ? 1 : 0;
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
              )
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

  String? get _highlightedTranscriptMoment {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    final best = parts.reduce((a, b) => a.length >= b.length ? a : b).trim();
    return best.length > 120 ? "${best.substring(0, 117)}..." : best;
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
                child: const VocalytixBrandButton(),
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
                    : "Loading Vocalytix...",
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
    final cleaned = lower.replaceAll(RegExp(r"[^\w\s]"), " ");
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
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: const [
          Icon(Icons.hexagon, size: 18, color: Color(0xFFFFA24C)),
          Icon(Icons.stop_rounded, size: 9, color: Color(0xFFFFF0E0)),
        ],
      ),
    );
  }
}
