import 'dart:async';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';
import 'qr_scanner_view.dart';
import 'kiosk_fullscreen.dart';

enum KioskStage {
  voterPin,         // Screen 1: Voter enters unique 6-digit Secret PIN
  voterIdCheckIn,   // Screen 2: Voter enters Voter ID / scans QR to verify and unlock
  otpVerification,  // 2nd layer verification OTP (if enabled)
  ballotCasting,    // Active secret ballot voting
  voteConfirmed,    // Confirmation receipt & 5-second auto-reset loop
}

class VenueKioskScreen extends ConsumerStatefulWidget {
  final String electionId;
  const VenueKioskScreen({super.key, required this.electionId});

  @override
  ConsumerState<VenueKioskScreen> createState() => _VenueKioskScreenState();
}

class _VenueKioskScreenState extends ConsumerState<VenueKioskScreen> {
  KioskStage _stage = KioskStage.voterPin;
  String _enteredVoterPin = '';
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _voterIdController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  // Active Voter & Ballot Session State
  String _voterName = '';
  String _voterId = '';
  String _maskedPhone = '';
  String _maskedEmail = '';
  String _sessionToken = '';
  bool _allowBoycott = true;
  List<dynamic> _ballotPositions = [];

  // Selections: { position_id: [candidate_id] }
  final Map<String, List<String>> _selectedCandidates = {};
  final Set<String> _boycottedPositions = {};
  final Map<String, String> _contestSearchQueries = {};

  // Post-Vote Receipt & Countdown
  String _receiptHash = '';
  String _votedAt = '';
  int _resetCountdown = 5;
  Timer? _resetTimer;

  @override
  void initState() {
    super.initState();
    _autoInitializeStation();
  }

  Future<void> _autoInitializeStation() async {
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post(
        ApiConstants.initializePollingStation(widget.electionId),
        data: {
          'station_name': 'Venue Kiosk Station #1',
          'station_code': 'BOOTH-01',
        },
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _pinController.dispose();
    _voterIdController.dispose();
    _otpController.dispose();
    _resetTimer?.cancel();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIONS & API CALLS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _unlockWithPin() async {
    final entered = _pinController.text.trim();
    if (entered.isEmpty) {
      setState(() => _errorMessage = 'Please enter your 6-digit Secret Voting PIN');
      return;
    }
    if (!RegExp(r'^\d{4,6}$').hasMatch(entered)) {
      setState(() => _errorMessage = 'Voting PIN must be numbers only (4 to 6 digits)');
      return;
    }
    enterFullscreen();

    setState(() {
      _enteredVoterPin = entered;
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dio = ref.read(apiClientProvider);
      final res = await dio.post(
        ApiConstants.kioskUnlock,
        data: {
          'election_id': widget.electionId,
          'pin': entered,
        },
      );

      final data = res.data;
      final requireOtp = data['require_otp'] as bool? ?? false;

      if (requireOtp) {
        setState(() {
          _voterName = data['voter_name'] ?? '';
          _voterId = data['voter_id'] ?? '';
          _maskedPhone = data['masked_phone'] ?? '';
          _maskedEmail = data['masked_email'] ?? '';
          _stage = KioskStage.otpVerification;
          _isLoading = false;
        });
      } else {
        _loadBallotSession(data);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = _extractErrorMessage(e);
      });
    }
  }

  Future<void> _checkInVoter() async {
    var identifier = _voterIdController.text.trim();
    if (identifier.isEmpty) {
      setState(() => _errorMessage = 'Please enter your Voter ID or Membership number');
      return;
    }

    if (identifier.startsWith('EMS-VOTER:')) {
      final parts = identifier.split(':');
      if (parts.length >= 2) identifier = parts[1].trim();
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dio = ref.read(apiClientProvider);
      final res = await dio.post(
        ApiConstants.kioskUnlock,
        data: {
          'election_id': widget.electionId,
          'voter_id': identifier,
          'pin': _enteredVoterPin,
        },
      );

      final data = res.data;
      final requireOtp = data['require_otp'] as bool? ?? false;

      if (requireOtp) {
        setState(() {
          _voterName = data['voter_name'] ?? '';
          _voterId = data['voter_id'] ?? identifier;
          _maskedPhone = data['masked_phone'] ?? '';
          _maskedEmail = data['masked_email'] ?? '';
          _stage = KioskStage.otpVerification;
          _isLoading = false;
        });
      } else {
        _loadBallotSession(data);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = _extractErrorMessage(e);
      });
    }
  }

  String _extractErrorMessage(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        if (data['error'] != null) return data['error'].toString();
        if (data['message'] != null) return data['message'].toString();
        if (data['detail'] != null) return data['detail'].toString();
      }
      return e.message ?? 'A network or server error occurred.';
    }
    return e.toString().replaceAll('Exception: ', '');
  }

  Future<void> _verifyOtpAndUnlock() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit verification code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dio = ref.read(apiClientProvider);
      final res = await dio.post(
        ApiConstants.kioskVerifyOtp,
        data: {
          'election_id': widget.electionId,
          'voter_id': _voterId,
          'otp': otp,
        },
      );

      _loadBallotSession(res.data);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = _extractErrorMessage(e);
      });
    }
  }

  void _loadBallotSession(Map<String, dynamic> data) {
    setState(() {
      _sessionToken = data['session_token'] as String? ?? '';
      _voterName = data['voter_name'] as String? ?? '';
      _voterId = data['voter_id'] as String? ?? '';
      _allowBoycott = data['allow_boycott'] as bool? ?? true;
      _ballotPositions = data['ballot'] as List<dynamic>? ?? [];
      _selectedCandidates.clear();
      _boycottedPositions.clear();
      _stage = KioskStage.ballotCasting;
      _isLoading = false;
      _errorMessage = null;
    });
  }

  void _toggleCandidate(String positionId, String candidateId, int maxSeats) {
    setState(() {
      _boycottedPositions.remove(positionId);
      final current = _selectedCandidates[positionId] ?? [];
      if (current.contains(candidateId)) {
        current.remove(candidateId);
      } else {
        if (maxSeats == 1) {
          _selectedCandidates[positionId] = [candidateId];
        } else {
          if (current.length < maxSeats) {
            current.add(candidateId);
            _selectedCandidates[positionId] = current;
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('You can select a maximum of $maxSeats candidate(s) for this position.'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    });
  }

  void _toggleBoycott(String positionId) {
    setState(() {
      if (_boycottedPositions.contains(positionId)) {
        _boycottedPositions.remove(positionId);
      } else {
        _boycottedPositions.add(positionId);
        _selectedCandidates.remove(positionId);
      }
    });
  }

  Future<void> _submitKioskBallot() async {
    // Check if at least one position is filled or explicitly abstained
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.how_to_vote_rounded, color: AppColors.primary),
            SizedBox(width: 10),
            Text('Confirm Secret Ballot Submission'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to cast your official secret ballot now?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'Positions Voted: ${_selectedCandidates.length + _boycottedPositions.length} of ${_ballotPositions.length}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            const Text(
              'Once cast, this action is final and cryptographically irreversible.',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Review Choices'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: const Text('Cast Official Ballot'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Build ballot data payload
      final ballotData = <String, dynamic>{};
      for (final p in _ballotPositions) {
        final pid = p['id'].toString();
        if (_boycottedPositions.contains(pid)) {
          ballotData[pid] = ['__BOYCOTT__'];
        } else if (_selectedCandidates.containsKey(pid)) {
          ballotData[pid] = _selectedCandidates[pid];
        }
      }

      final dio = ref.read(apiClientProvider);
      final res = await dio.post(
        ApiConstants.kioskCast,
        data: {
          'session_token': _sessionToken,
          'election_id': widget.electionId,
          'ballot_data': ballotData,
          'device_identifier': 'kiosk_booth_station_01',
        },
      );

      setState(() {
        _receiptHash = res.data['receipt_hash'] ?? 'CRYPTOGRAPHIC-RECORDED';
        _votedAt = res.data['voted_at'] ?? DateTime.now().toIso8601String();
        _stage = KioskStage.voteConfirmed;
        _resetCountdown = 5;
        _isLoading = false;
      });

      _startAutoResetTimer();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = _extractErrorMessage(e);
      });
    }
  }

  void _startAutoResetTimer() {
    _resetTimer?.cancel();
    _resetTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resetCountdown <= 1) {
        timer.cancel();
        _resetKioskToStandby();
      } else {
        setState(() => _resetCountdown--);
      }
    });
  }

  void _resetKioskToStandby() {
    _resetTimer?.cancel();
    setState(() {
      _stage = KioskStage.voterPin;
      _enteredVoterPin = '';
      _pinController.clear();
      _voterIdController.clear();
      _otpController.clear();
      _voterName = '';
      _voterId = '';
      _sessionToken = '';
      _selectedCandidates.clear();
      _boycottedPositions.clear();
      _receiptHash = '';
      _errorMessage = null;
      _isLoading = false;
    });
  }

  void _showOfficerExitDialog() {
    final exitPinController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: AppColors.primary),
            SizedBox(width: 10),
            Text('Officer Authorization Exit'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter Station Security PIN to exit Kiosk Booth mode:'),
            const SizedBox(height: 14),
            TextField(
              controller: exitPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Station PIN',
                hintText: 'e.g. 1234',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (exitPinController.text.trim() == '1234' || exitPinController.text.trim() == '0000') {
                exitFullscreen();
                Navigator.pop(ctx);
                context.pop();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Incorrect Station Security PIN')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Unlock & Exit'),
          ),
        ],
      ),
    );
  }

  void _showQrScannerModal() {
    final qrInputController = TextEditingController();
    String? cameraError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF334155))),
            title: const Row(
              children: [
                Icon(Icons.qr_code_scanner_rounded, color: Color(0xFFD8B4FE)),
                SizedBox(width: 10),
                Text('Live Camera QR Scanner', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Live Camera Stream Container
                  Container(
                    height: 240,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                    ),
                    child: buildLiveQrScanner(
                      onScanned: (decodedCode) {
                        Navigator.pop(ctx);
                        _voterIdController.text = decodedCode;
                        _checkInVoter();
                      },
                      onError: (err) {
                        setModalState(() {
                          cameraError = err;
                        });
                      },
                    ),
                  ),
                  if (cameraError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      cameraError!,
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 11.5),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: qrInputController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Or Paste / Scan Code directly',
                      labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                      hintText: 'e.g. V009 or EMS-VOTER:V009:...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final val = qrInputController.text.trim();
                  if (val.isNotEmpty) {
                    _voterIdController.text = val;
                    Navigator.pop(ctx);
                    _checkInVoter();
                  }
                },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Process Check-in'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UI BUILD METHODS
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final electionAsync = ref.watch(electionProvider(widget.electionId));

    return PopScope(
      canPop: false, // Prevent accidental Android back button exit
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showOfficerExitDialog();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A), // Dark professional Kiosk theme
        body: electionAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
          error: (e, _) => Center(
            child: Text('Failed to load election: $e', style: const TextStyle(color: Colors.white)),
          ),
          data: (election) {
            final isCasting = _stage == KioskStage.ballotCasting;
            return SafeArea(
              top: !isCasting,
              bottom: !isCasting,
              left: !isCasting,
              right: !isCasting,
              child: Column(
                children: [
                  if (!isCasting) _buildKioskHeader(election),
                  Expanded(
                    child: Center(
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: isCasting ? double.infinity : (_stage == KioskStage.voterIdCheckIn ? 680 : 580),
                        ),
                        margin: isCasting ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: _buildStageContent(election),
                      ),
                    ),
                  ),
                  if (!isCasting) _buildKioskFooter(election),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildKioskHeader(ElectionModel election) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(bottom: BorderSide(color: Color(0xFF334155))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple.withValues(alpha: 0.5)),
            ),
            child: const Row(
              children: [
                Icon(Icons.storefront_rounded, color: Color(0xFFD8B4FE), size: 18),
                SizedBox(width: 8),
                Text(
                  'METHOD 2 • VENUE KIOSK BOOTH',
                  style: TextStyle(color: Color(0xFFD8B4FE), fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  election.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  election.venueName.isNotEmpty ? '📍 ${election.venueName} • Station #1' : '📍 Official Polling Booth Station',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                  maxLines: 1,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen_rounded, color: Color(0xFF94A3B8)),
            tooltip: 'Toggle Fullscreen',
            onPressed: toggleFullscreen,
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF94A3B8)),
            tooltip: 'Officer Exit Kiosk Mode',
            onPressed: _showOfficerExitDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildKioskFooter(ElectionModel election) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(top: BorderSide(color: Color(0xFF334155))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(Icons.security_rounded, color: Color(0xFF10B981), size: 14),
              SizedBox(width: 6),
              Text(
                'End-to-End Cryptographic Secret Ballot • SHA-256 Verified',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
            ],
          ),
          Text(
            'Kiosk Mode Active • Station Locked',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildStageContent(ElectionModel election) {
    if (_stage == KioskStage.ballotCasting) {
      return _buildBallotCastingView(election);
    }
    return SingleChildScrollView(
      child: switch (_stage) {
        KioskStage.voterPin => _buildVoterPinCard(),
        KioskStage.voterIdCheckIn => _buildVoterIdCard(election),
        KioskStage.otpVerification => _buildOtpVerificationCard(),
        KioskStage.voteConfirmed => _buildVoteConfirmationCard(),
        KioskStage.ballotCasting => _buildBallotCastingView(election),
      },
    );
  }

  // 1. Screen 1: Unique Secret Voter PIN Entry
  Widget _buildVoterPinCard() {
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFF334155))),
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4), width: 2),
              ),
              child: const Icon(Icons.pin_rounded, color: Color(0xFFF59E0B), size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              'Enter Your Secret Voting PIN',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter the 6-digit Secret Voting PIN printed on your official voter token slip.\n(मतदान गर्न आफ्नो ६-अङ्के गोप्य पिन प्रविष्ट गर्नुहोस्)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 26),
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              obscureText: true,
              textAlign: TextAlign.center,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '••••••',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF334155))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF334155))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 2)),
              ),
              onSubmitted: (_) => _unlockWithPin(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _unlockWithPin,
                icon: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black87, strokeWidth: 2))
                    : const Icon(Icons.lock_open_rounded, size: 20),
                label: const Text('Unlock & Cast Vote (मतपत्र खोल्नुहोस्)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                  _stage = KioskStage.voterIdCheckIn;
                });
              },
              icon: const Icon(Icons.badge_outlined, size: 16, color: Color(0xFF94A3B8)),
              label: const Text(
                'Or Check In via Voter ID / Scan QR Code (वा मतदाता परिचयपत्र/QR बाट)',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 2. Screen 2: Voter ID & Ballot Unlock
  Widget _buildVoterIdCard(ElectionModel election) {
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFF334155))),
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.purple.withValues(alpha: 0.4), width: 2),
              ),
              child: const Icon(Icons.badge_rounded, color: Color(0xFFD8B4FE), size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              'Step 2 • Enter Your Voter ID',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter your Voter ID number to unlock your official secret ballot.\n(मतदाता परिचयपत्र वा सदस्यता नम्बर प्रविष्ट गर्नुहोस्)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 16),
            // Verified PIN indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'PIN Entered: ${_enteredVoterPin.replaceAll(RegExp(r'.'), '•')}',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _voterIdController,
              keyboardType: TextInputType.text,
              textAlign: TextAlign.center,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              decoration: InputDecoration(
                labelText: 'Voter ID / Membership No (मतदाता परिचयपत्र)',
                labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                hintText: 'e.g. NEA-VOTE-101',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
                prefixIcon: const Icon(Icons.badge_rounded, color: AppColors.primaryLight),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF334155))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF334155))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primaryLight, width: 2)),
              ),
              onSubmitted: (_) => _checkInVoter(),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _stage = KioskStage.voterPin;
                      _errorMessage = null;
                    });
                  },
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                  tooltip: 'Back to PIN entry',
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _checkInVoter,
                      icon: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.lock_open_rounded, size: 20),
                      label: const FittedBox(child: Text('Unlock Ballot (मतपत्र खोल्नुहोस्)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5))),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => _showQrScannerModal(),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 20, color: Color(0xFFD8B4FE)),
                      label: const FittedBox(child: Text('Scan QR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFD8B4FE)))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF8B5CF6)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 3. 2nd Layer OTP Verification
  Widget _buildOtpVerificationCard() {
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFF334155))),
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mark_chat_unread_rounded, color: Color(0xFF60A5FA), size: 48),
            const SizedBox(height: 18),
            const Text(
              '2nd-Layer Security Verification',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Hello $_voterName ($_voterId),\na 6-digit unlock code was sent to ${_maskedPhone.isNotEmpty ? _maskedPhone : _maskedEmail}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null) ...[
              Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '------',
                counterText: '',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF334155))),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => setState(() => _stage = KioskStage.voterIdCheckIn),
                  child: const Text('Back / Re-enter ID', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _verifyOtpAndUnlock,
                  icon: _isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.verified_user_rounded, size: 18),
                  label: const Text('Verify & Open Ballot', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 4. Fullscreen Official Ballot Casting (Matches BallotScreen aesthetic)
  Widget _buildBallotCastingView(ElectionModel election) {
    final now = DateTime.now();
    final nepaliNow = now.toNepaliDateTime();
    final nepaliDateStr = '${NepaliDateFormat('yyyy/MM/dd').format(nepaliNow)} BS';
    final votingTime = DateFormat('hh:mm a').format(now);

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.unknown,
        },
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        child: Column(
          children: [
            // Official Red Stamp Header Banner
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFB91C1C).withValues(alpha: 0.5), width: 1.2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF331317), Color(0xFF1E293B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 36, height: 36, child: CustomPaint(painter: const _KioskSwastikPainter(color: Color(0xFFB91C1C)))),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFB91C1C).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFB91C1C).withValues(alpha: 0.4)),
                                ),
                                child: const Text(
                                  'मतपत्र — OFFICIAL BALLOT',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: Color(0xFFFCA5A5), letterSpacing: 1.2),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                election.title,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              // Sleek Professional Metadata Line (No bulky boxes!)
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 14,
                                runSpacing: 6,
                                children: [
                                  _buildInlineKioskMeta(
                                    Icons.person_outline_rounded,
                                    'VOTER NAME',
                                    _voterName.isNotEmpty ? _voterName : 'Authenticated Voter',
                                  ),
                                  _buildKioskDotSeparator(),
                                  _buildInlineKioskMeta(
                                    Icons.badge_outlined,
                                    'VOTER ID',
                                    _voterId.isNotEmpty ? _voterId : '—',
                                  ),
                                  _buildKioskDotSeparator(),
                                  _buildInlineKioskMeta(
                                    Icons.calendar_today_outlined,
                                    'VOTING DATE',
                                    nepaliDateStr,
                                  ),
                                  _buildKioskDotSeparator(),
                                  _buildInlineKioskMeta(
                                    Icons.access_time_rounded,
                                    'VOTING TIME',
                                    votingTime,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        SizedBox(width: 36, height: 36, child: CustomPaint(painter: const _KioskSwastikPainter(color: Color(0xFFB91C1C)))),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 20),
                          tooltip: 'Officer Exit Station',
                          onPressed: _showOfficerExitDialog,
                        ),
                      ],
                    ),
                  ),

                  // Bottom Cryptographic Assurance Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(17)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified_user_outlined, size: 14, color: Color(0xFF38BDF8)),
                        SizedBox(width: 8),
                        Text(
                          'End-to-End Cryptographically Sealed In-Person Kiosk Ballot • Station #1',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Contests
          ..._ballotPositions.map((pos) {
            final posId = pos['id'].toString();
            final title = pos['title'] as String? ?? 'Designation';
            final isSam = pos['voting_method'] == 'samanupatik' || posId == 'pr_ballot';
            final maxVotes = (pos['max_votes_per_voter'] as int?) ?? 1;
            final seats = (isSam || maxVotes == 1) ? 1 : (pos['seats_available'] as int? ?? 1);
            final candidates = pos['candidates'] as List<dynamic>? ?? [];
            final isBoycotted = _boycottedPositions.contains(posId);
            final selectedList = _selectedCandidates[posId] ?? [];
            final isComplete = selectedList.length == seats;

            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF334155)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Position Header
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F172A),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(19)),
                      border: Border(bottom: BorderSide(color: Color(0xFF334155))),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.military_tech_rounded, color: AppColors.primaryLight, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isSam ? 'Select 1 Political Party / Symbol' : 'Select up to $seats candidate(s) for this designation',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isBoycotted
                                ? Colors.orange.withValues(alpha: 0.2)
                                : (isComplete ? Colors.green.withValues(alpha: 0.2) : Colors.white10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isBoycotted ? Colors.orange : (isComplete ? Colors.green : Colors.white24),
                            ),
                          ),
                          child: Text(
                            isBoycotted ? 'ABSTAINED' : '${selectedList.length}/$seats Selected',
                            style: TextStyle(
                              color: isBoycotted ? Colors.orange : (isComplete ? const Color(0xFF34D399) : Colors.white70),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // In-Contest Search Filter (for positions with 8 or more candidates)
                  if (candidates.length >= 8)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      child: TextField(
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                          hintText: 'Search candidates by name, number, or manifesto...',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                        ),
                        onChanged: (val) => setState(() => _contestSearchQueries[posId] = val.trim().toLowerCase()),
                      ),
                    ),

                  // Candidate Cards Grid
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final query = _contestSearchQueries[posId] ?? '';
                        final filteredCandidates = query.isEmpty
                            ? candidates
                            : candidates.where((c) {
                                final name = '${c["name"] ?? c["first_name"] ?? ""} ${c["last_name"] ?? ""}'.toLowerCase();
                                final manifesto = (c['manifesto'] as String? ?? '').toLowerCase();
                                return name.contains(query) || manifesto.contains(query);
                              }).toList();

                        int crossAxisCount;
                        if (constraints.maxWidth >= 1500) {
                          crossAxisCount = 4;
                        } else if (constraints.maxWidth >= 1100) {
                          crossAxisCount = 3;
                        } else if (constraints.maxWidth >= 680) {
                          crossAxisCount = 2;
                        } else {
                          crossAxisCount = 1;
                        }
                        const spacing = 16.0;
                        final totalSpacing = spacing * (crossAxisCount - 1);
                        final itemWidth = (constraints.maxWidth - totalSpacing) / crossAxisCount;

                        if (filteredCandidates.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'No candidates match your search.',
                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                              ),
                            ),
                          );
                        }

                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: filteredCandidates.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final cand = entry.value;
                            final cid = cand['id'].toString();
                            final name = '${cand["name"] ?? cand["first_name"] ?? ""} ${cand["last_name"] ?? ""}'.trim();
                            final manifesto = cand['manifesto'] as String? ?? '';
                            final photoUrl = cand['photo_url'] as String? ?? '';
                            final partyName = (cand['party_name'] as String? ?? '').trim();
                            final panelName = (cand['panel_name'] as String? ?? '').trim();
                            final symbolName = (cand['symbol_name'] as String? ?? '').trim();
                            final symbolImage = (cand['symbol_image'] as String? ?? '').trim();
                            final isSelected = selectedList.contains(cid);
                            final letterBadge = String.fromCharCode(65 + (idx % 26));

                            return SizedBox(
                              width: itemWidth,
                              child: InkWell(
                                onTap: () => _toggleCandidate(posId, cid, seats),
                                borderRadius: BorderRadius.circular(16),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFB91C1C).withValues(alpha: 0.15)
                                        : const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFFB91C1C) : const Color(0xFF334155),
                                      width: isSelected ? 2 : 1,
                                    ),
                                    boxShadow: [
                                      if (isSelected)
                                        BoxShadow(color: const Color(0xFFB91C1C).withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3)),
                                    ],
                                  ),
                                  child: Stack(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Letter Badge / Photo / Large Symbol
                                            Container(
                                              width: 60,
                                              height: 60,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1E293B),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: const Color(0xFF334155), width: 1),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(11),
                                                child: photoUrl.isNotEmpty
                                                    ? Image.network(
                                                        ApiConstants.getFullImageUrl(photoUrl) ?? photoUrl,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (ctx, err, stack) => (symbolImage.isNotEmpty
                                                            ? Padding(
                                                                padding: const EdgeInsets.all(5.0),
                                                                child: Image.network(symbolImage, fit: BoxFit.contain),
                                                              )
                                                            : _buildKioskLetterAvatar(letterBadge)),
                                                      )
                                                    : (symbolImage.isNotEmpty
                                                        ? Padding(
                                                            padding: const EdgeInsets.all(5.0),
                                                            child: Image.network(
                                                              symbolImage,
                                                              fit: BoxFit.contain,
                                                              errorBuilder: (ctx, err, stack) => _buildKioskLetterAvatar(letterBadge),
                                                            ),
                                                          )
                                                        : (symbolName.isNotEmpty
                                                            ? const Center(child: Icon(Icons.how_to_vote_rounded, color: Color(0xFFF59E0B), size: 26))
                                                            : _buildKioskLetterAvatar(letterBadge))),
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          name.isNotEmpty ? name : 'Candidate $letterBadge',
                                                          style: TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 15,
                                                            color: isSelected ? const Color(0xFFFCA5A5) : Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                      if (symbolName.isNotEmpty) ...[
                                                        const SizedBox(width: 6),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                                            borderRadius: BorderRadius.circular(5),
                                                            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              const Icon(Icons.how_to_vote_rounded, size: 10.5, color: Color(0xFFF59E0B)),
                                                              const SizedBox(width: 3),
                                                              Text(
                                                                symbolName,
                                                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFDE68A)),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  if (manifesto.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      manifesto,
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8), height: 1.3),
                                                    ),
                                                  ],
                                                  if (partyName.isNotEmpty || panelName.isNotEmpty) ...[
                                                    const SizedBox(height: 6),
                                                    Wrap(
                                                      spacing: 6,
                                                      runSpacing: 4,
                                                      children: [
                                                        if (partyName.isNotEmpty)
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFF1E3A8A).withValues(alpha: 0.4),
                                                              borderRadius: BorderRadius.circular(5),
                                                              border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                const Icon(Icons.flag_rounded, size: 10.5, color: Color(0xFF60A5FA)),
                                                                const SizedBox(width: 4),
                                                                Text(partyName, style: const TextStyle(color: Color(0xFFBFDBFE), fontSize: 10.5, fontWeight: FontWeight.bold)),
                                                              ],
                                                            ),
                                                          ),
                                                        if (panelName.isNotEmpty)
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFF581C87).withValues(alpha: 0.4),
                                                              borderRadius: BorderRadius.circular(5),
                                                              border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                const Icon(Icons.groups_rounded, size: 10.5, color: Color(0xFFA78BFA)),
                                                                const SizedBox(width: 4),
                                                                Text(panelName, style: const TextStyle(color: Color(0xFFE9D5FF), fontSize: 10.5, fontWeight: FontWeight.bold)),
                                                              ],
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Stamp Indicator on Selection
                                      Positioned(
                                        top: 10,
                                        right: 10,
                                        child: isSelected
                                            ? Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFB91C1C).withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: const Color(0xFFB91C1C), width: 1.5),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child: CustomPaint(painter: _KioskSwastikPainter(color: Color(0xFFB91C1C))),
                                                    ),
                                                    SizedBox(width: 4),
                                                    Text('छाप लगाइयो', style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 10, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                              )
                                            : Container(
                                                width: 22,
                                                height: 22,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: const Color(0xFF64748B), width: 1.5),
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),

                  // NOTA / Abstain Card
                  if (_allowBoycott)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: InkWell(
                        onTap: () => _toggleBoycott(posId),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isBoycotted ? const Color(0xFFD97706).withValues(alpha: 0.15) : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isBoycotted ? const Color(0xFFD97706) : const Color(0xFF334155),
                              width: isBoycotted ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isBoycotted ? const Color(0xFFD97706) : Colors.grey.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.do_not_disturb_alt_rounded, size: 18, color: isBoycotted ? Colors.white : Colors.grey),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('No Vote / None of the Above (NOTA)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white)),
                                    SizedBox(height: 2),
                                    Text('I choose to abstain from casting a vote for this position.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
                                  ],
                                ),
                              ),
                              Checkbox(
                                value: isBoycotted,
                                activeColor: const Color(0xFFD97706),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                onChanged: (_) => _toggleBoycott(posId),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          // Submit Action Button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _submitKioskBallot,
              icon: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.how_to_vote_rounded, size: 22),
              label: const Text('Review & Cast Official Ballot (मतपत्र समीक्षा एवं मतदान)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

  Widget _buildInlineKioskMeta(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF94A3B8),
            letterSpacing: 0.3,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildKioskDotSeparator() {
    return Container(
      width: 4,
      height: 4,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: const BoxDecoration(
        color: Color(0xFF475569),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildKioskLetterAvatar(String letter) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
        ),
      ),
    );
  }

  // 5. Confirmation & 5-Second Automated Loop
  Widget _buildVoteConfirmationCard() {
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFF10B981))),
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF064E3B),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 56),
            ),
            const SizedBox(height: 20),
            const Text(
              'Ballot Cast Successfully!',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your vote has been cryptographically recorded on this official kiosk station.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
            ),
            const SizedBox(height: 20),

            // Receipt Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CRYPTOGRAPHIC RECEIPT HASH (SHA-256):', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(_receiptHash, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                  if (_votedAt.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Recorded Timestamp: $_votedAt', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),

            // 5-Second Auto-Reset Progress & Countdown Loop
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _resetCountdown / 5.0,
                        backgroundColor: Colors.purple.withValues(alpha: 0.2),
                        color: const Color(0xFFD8B4FE),
                        strokeWidth: 4,
                      ),
                      Text(
                        '$_resetCountdown',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Automated Station Reset Loop',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        Text(
                          'Kiosk will automatically reset for the next voter in queue.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _resetKioskToStandby,
                icon: const Icon(Icons.skip_next_rounded, size: 20),
                label: const Text('Next Voter Now (अर्को मतदाता)', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KioskSwastikPainter extends CustomPainter {
  final Color color;
  const _KioskSwastikPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final double w = size.width;
    final double h = size.height;
    final double t = w / 3;
    final double c = w / 3;

    final path = Path();
    path.addRect(Rect.fromLTWH(t, t, c, c));
    path.addRect(Rect.fromLTWH(t, 0, c, t));
    path.addRect(Rect.fromLTWH(t, h - t, c, t));
    path.addRect(Rect.fromLTWH(0, t, t, c));
    path.addRect(Rect.fromLTWH(w - t, t, t, c));
    path.addRect(Rect.fromLTWH(w - t, 0, t, t));
    path.addRect(Rect.fromLTWH(0, h - t, t, t));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_KioskSwastikPainter old) => old.color != color;
}

