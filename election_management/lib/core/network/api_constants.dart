// API constants and environment configuration
class ApiConstants {
  // Use 10.0.2.2 for Android emulator, 127.0.0.1 for web/desktop
  static const String baseUrl = 'http://127.0.0.1:8000/v1';
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

  // Elections
  static const String elections = '/elections/';
  static String electionDetail(String id) => '/elections/$id/';
  static String electionPublish(String id) => '/elections/$id/publish/';
  static String electionAdvanceState(String id) => '/elections/$id/advance_state/';
  static String electionHistory(String id) => '/elections/$id/history/';
  static String electionPositions(String id) => '/elections/$id/positions/';
  static String electionCandidates(String id) => '/elections/$id/candidates/';
  static String approveCandidate(String eid, String cid) =>
      '/elections/$eid/candidates/$cid/approve/';
  static String rejectCandidate(String eid, String cid) =>
      '/elections/$eid/candidates/$cid/reject/';

  // Members
  static const String members = '/members/';
  static String memberDetail(String id) => '/members/$id/';

  // Voting
  static String ballot(String eid) => '/elections/$eid/voting/ballot/';
  static String votingSession(String eid) => '/elections/$eid/voting/session/';
  static String castVote(String eid) => '/elections/$eid/voting/cast/';

  // Results
  static String results(String eid) => '/elections/$eid/results/results/';

  // Organization
  static const String organizationProfile = '/organization/';
  static const String organizationStats = '/organization/stats/';
}
