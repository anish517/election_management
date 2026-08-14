// API constants and environment configuration
class ApiConstants {
  // --- Environment Switcher ---
  // Uncomment the ONE you want to use, and comment out the rest:

  // 1. For Web / Desktop testing
  static const String baseUrl = 'http://127.0.0.1:8000/v1';

  // 2. For Android Emulator testing
  // static const String baseUrl = 'http://10.0.2.2:8000/v1';

  // 3. For Physical Phone testing (make sure backend runs with 0.0.0.0:8000)
  //static const String baseUrl = 'http://192.168.1.9:8000/v1';
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Auth endpoints
  static const String register = '/auth/register/';
  static const String login = '/auth/login/';
  static const String logout = '/auth/logout/';
  static const String tokenRefresh = '/auth/token/refresh/';
  static const String me = '/auth/me/';
  static const String otpRequest = '/auth/otp/request/';
  static const String otpVerify = '/auth/otp/verify/';

  // Core endpoints
  static const String fileUpload = '/upload/';

  // Elections
  static const String elections = '/elections/';
  static String electionDetail(String id) => '/elections/$id/';
  static String electionPublish(String id) => '/elections/$id/publish/';
  static String electionAdvanceState(String id) =>
      '/elections/$id/advance_state/';
  static String electionHistory(String id) => '/elections/$id/history/';
  static String electionTurnout(String id) => '/elections/$id/turnout/';
  static String electionVotingActivity(String id) =>
      '/elections/$id/voting_activity/';
  static String electionPositions(String id) => '/elections/$id/positions/';
  static String electionPositionDetail(String eid, String pid) =>
      '/elections/$eid/positions/$pid/';
  static String electionQuotas(String id) => '/elections/$id/quotas/';
  static String electionQuotaDetail(String eid, String qid) =>
      '/elections/$eid/quotas/$qid/';
  static String electionCandidates(String id) => '/elections/$id/candidates/';
  static String electionVoters(String id) => '/elections/$id/voters/';
  static String approveCandidate(String eid, String cid) =>
      '/elections/$eid/candidates/$cid/approve/';
  static String rejectCandidate(String eid, String cid) =>
      '/elections/$eid/candidates/$cid/reject/';
  static String electionNotices(String id) => '/elections/$id/notices/';
  static String electionNoticeDetail(String eid, String nid) =>
      '/elections/$eid/notices/$nid/';
  static String broadcastEmail(String id) => '/elections/$id/broadcast_email/';
  static String electionCommittees(String id) => '/elections/$id/committees/';
  static String electionCreateCommittee(String id) =>
      '/elections/$id/create_committee/';
  static String electionUpdateCommittee(String eid, String cid) =>
      '/elections/$eid/committees/$cid/update/';
  static String electionDeleteCommittee(String eid, String cid) =>
      '/elections/$eid/committees/$cid/delete/';
  static String electionAssignments(String id) => '/elections/$id/assignments/';

  // Members
  static const String members = '/members/';
  static String memberDetail(String id) => '/members/$id/';
  static const String importCsv = '/members/import_csv/';
  static const String exportCsv = '/members/export_csv/';

  static String previewElectionVotersCsv(String electionId) =>
      '/elections/$electionId/voters/preview_csv/';
  static String importElectionVotersCsv(String electionId) =>
      '/elections/$electionId/voters/import_csv/';
  static String exportElectionVotersCsv(String electionId) =>
      '/elections/$electionId/voters/export_csv/';
  static String importElectionMembers(String electionId) =>
      '/elections/$electionId/voters/import_members/';
  static String importExternalApiVoters(String electionId) =>
      '/elections/$electionId/voters/import_external_api/';

  // Voting
  static const String votingHistory = '/voting/history/';
  static String ballot(String eid) => '/elections/$eid/voting/ballot/';
  static String votingSession(String eid) => '/elections/$eid/voting/session/';
  static String castVote(String eid) => '/elections/$eid/voting/cast/';

  // Results
  static String results(String eid) => '/elections/$eid/results/results/';

  // Auditor Verification Portal
  // Helpers
  static String? getFullImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;

    // Base URL contains '/v1', so we need the origin
    final origin = baseUrl.replaceAll('/v1', '');
    if (path.startsWith('/')) {
      return '$origin$path';
    }
    return '$origin/$path';
  }

  static String auditExport(String eid) => '/elections/$eid/audit/export/';
  static String auditVerifyHash(String eid) =>
      '/elections/$eid/audit/verify-hash/';
  static String auditReceiptLookup(String eid, String hash) =>
      '/elections/$eid/audit/receipt/$hash/';

  // Organization
  static const String organizationProfile = '/organization/';
  static const String organizationStats = '/organization/stats/';
}
