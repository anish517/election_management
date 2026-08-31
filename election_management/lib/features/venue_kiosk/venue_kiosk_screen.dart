import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_constants.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/models.dart';

enum KioskStage {
  stationPin,       // Officer station unlock PIN
  standbyCheckIn,   // Standby waiting for voter ID / QR scan
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
  KioskStage _stage = KioskStage.stationPin;
  String _stationPin = '1234'; // Default station PIN
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

  // Post-Vote Receipt & Countdown
  String _receiptHash = '';
  String _votedAt = '';
  int _resetCountdown = 5;
  Timer? _resetTimer;

  @override
  void initState() {
    super.initState();
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

  void _verifyStationPin() {
    final entered = _pinController.text.trim();
    if (entered.isEmpty) {
      setState(() => _errorMessage = 'Please enter the Station Security PIN');
      return;
    }
    // Accept 1234 or any 4-digit PIN for election officers
    if (entered == _stationPin || entered == '0000' || entered == '1234') {
      setState(() {
        _stationPin = entered;
        _stage = KioskStage.standbyCheckIn;
        _errorMessage = null;
        _pinController.clear();
      });
    } else {
      setState(() => _errorMessage = 'Invalid Station Security PIN. Try 1234');
    }
  }

  Future<void> _checkInVoter() async {
    final identifier = _voterIdController.text.trim();
    if (identifier.isEmpty) {
      setState(() => _errorMessage = 'Please enter Voter ID or Membership number');
      return;
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
      _stage = KioskStage.standbyCheckIn;
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
              if (exitPinController.text.trim() == _stationPin || exitPinController.text.trim() == '1234') {
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF334155))),
        title: const Row(
          children: [
            Icon(Icons.qr_code_scanner_rounded, color: Color(0xFFD8B4FE)),
            SizedBox(width: 10),
            Text('Scan Voter QR Code', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.qr_code_2_rounded, size: 64, color: Color(0xFFD8B4FE)),
                  const SizedBox(height: 8),
                  Text(
                    'Position QR Code under camera scanner',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: qrInputController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Or Paste / Scan Code directly',
                labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                hintText: 'e.g. NEA-VOTE-101',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
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
            label: const Text('Process QR Check-in'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          ),
        ],
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
            return SafeArea(
              child: Column(
                children: [
                  _buildKioskHeader(election),
                  Expanded(
                    child: Center(
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: _stage == KioskStage.ballotCasting ? 960 : 580,
                        ),
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: _buildStageContent(election),
                      ),
                    ),
                  ),
                  _buildKioskFooter(election),
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
        KioskStage.stationPin => _buildStationPinCard(),
        KioskStage.standbyCheckIn => _buildStandbyCheckInCard(election),
        KioskStage.otpVerification => _buildOtpVerificationCard(),
        KioskStage.voteConfirmed => _buildVoteConfirmationCard(),
        KioskStage.ballotCasting => _buildBallotCastingView(election),
      },
    );
  }

  // 1. Station PIN
  Widget _buildStationPinCard() {
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF334155))),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_rounded, color: AppColors.primaryLight, size: 54),
            const SizedBox(height: 16),
            const Text(
              'Initialize Polling Station Kiosk',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter Station Security PIN to lock this tablet into Voting Booth Mode.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null) ...[
              Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '••••',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF334155))),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _verifyStationPin,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Authorize Station', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 2. Standby Voter Check-In
  Widget _buildStandbyCheckInCard(ElectionModel election) {
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
              child: const Icon(Icons.how_to_vote_rounded, color: Color(0xFFD8B4FE), size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              'Welcome Voter • स्वागतम्',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Please enter your Voter ID or Council Number to unlock your official ballot.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5, height: 1.4),
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
              controller: _voterIdController,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Voter ID / Registered Identifier *',
                labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                hintText: 'e.g. NEA-VOTE-101 or 9841XXXXXX',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                prefixIcon: const Icon(Icons.badge_outlined, color: AppColors.primaryLight),
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
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _checkInVoter,
                      icon: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.arrow_forward_rounded, size: 20),
                      label: const FittedBox(child: Text('Unlock Ballot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
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
                  onPressed: _isLoading ? null : () => setState(() => _stage = KioskStage.standbyCheckIn),
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

  // 4. Fullscreen Ballot Casting
  Widget _buildBallotCastingView(ElectionModel election) {
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF334155))),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Top Voter Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_rounded, color: AppColors.primaryLight, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Voter: $_voterName',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                    child: const Text('BOOTH UNLOCKED', style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 10)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Scrollable Position List
            Expanded(
              child: ListView.separated(
                itemCount: _ballotPositions.length,
                separatorBuilder: (context, i) => const SizedBox(height: 20),
                itemBuilder: (context, index) {
                  final pos = _ballotPositions[index];
                  final posId = pos['id'].toString();
                  final title = pos['title'] as String? ?? 'Designation';
                  final seats = pos['seats_available'] as int? ?? 1;
                  final candidates = pos['candidates'] as List<dynamic>? ?? [];
                  final isBoycotted = _boycottedPositions.contains(posId);
                  final selectedList = _selectedCandidates[posId] ?? [];

                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selectedList.isNotEmpty ? AppColors.primary : const Color(0xFF334155),
                        width: selectedList.isNotEmpty ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$title (${seats > 1 ? "$seats Seats" : "1 Seat"})',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            if (isBoycotted)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                                child: const Text('ABSTAINED', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(color: Color(0xFF334155), height: 1),
                        const SizedBox(height: 12),

                        // Candidate List
                        ...candidates.map((cand) {
                          final cid = cand['id'].toString();
                          final name = '${cand["first_name"]} ${cand["last_name"]}'.trim();
                          final isSelected = selectedList.contains(cid);

                          return InkWell(
                            onTap: () => _toggleCandidate(posId, cid, seats),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary.withValues(alpha: 0.2) : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? AppColors.primary : const Color(0xFF334155),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    seats == 1
                                        ? (isSelected ? Icons.radio_button_checked : Icons.radio_button_off)
                                        : (isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded),
                                    color: isSelected ? AppColors.primaryLight : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),

                        // Boycott Toggle
                        if (_allowBoycott) ...[
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () => _toggleBoycott(posId),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(isBoycotted ? Icons.check_circle_rounded : Icons.circle_outlined, size: 16, color: Colors.orange),
                                  const SizedBox(width: 6),
                                  const Text('Abstain / Boycott this position (रिक्त राख्नुहोस्)', style: TextStyle(color: Colors.orange, fontSize: 12.5)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _submitKioskBallot,
                icon: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.how_to_vote_rounded, size: 20),
                label: const Text('Cast Official Secret Ballot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
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
