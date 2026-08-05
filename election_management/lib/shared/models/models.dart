// Data models for API responses

class UserModel {
  final String id;
  final String email;
  final String phone;
  final String role;
  final String roleDisplay;
  final String organization;
  final String organizationName;
  final bool is2faEnabled;
  final String? lastLoginAt;

  const UserModel({
    required this.id,
    required this.email,
    required this.phone,
    required this.role,
    required this.roleDisplay,
    required this.organization,
    required this.organizationName,
    required this.is2faEnabled,
    this.lastLoginAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        role: json['role'] as String,
        roleDisplay: json['role_display'] as String? ?? '',
        organization: json['organization'] as String,
        organizationName: json['organization_name'] as String? ?? '',
        is2faEnabled: json['is_2fa_enabled'] as bool? ?? false,
        lastLoginAt: json['last_login_at'] as String?,
      );

  bool get isOrgAdmin => role == 'org_admin';
  bool get isElectionOfficer => role == 'election_officer';
  bool get isObserver => role == 'observer';
  bool get isMember => role == 'member';
  bool get canManageElections => isOrgAdmin || isElectionOfficer;
}

class ElectionModel {
  final String id;
  final String title;
  final String description;
  final String state;
  final bool isSecretBallot;
  final bool liveTurnoutEnabled;
  final String resultsVisibility;
  final String? nominationOpenAt;
  final String? nominationCloseAt;
  final String? votingStartAt;
  final String? votingEndAt;
  final List<PositionModel> positions;
  final String createdAt;

  const ElectionModel({
    required this.id,
    required this.title,
    required this.description,
    required this.state,
    required this.isSecretBallot,
    required this.liveTurnoutEnabled,
    required this.resultsVisibility,
    this.nominationOpenAt,
    this.nominationCloseAt,
    this.votingStartAt,
    this.votingEndAt,
    required this.positions,
    required this.createdAt,
  });

  factory ElectionModel.fromJson(Map<String, dynamic> json) => ElectionModel(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        state: json['state'] as String,
        isSecretBallot: json['is_secret_ballot'] as bool? ?? true,
        liveTurnoutEnabled: json['live_turnout_enabled'] as bool? ?? false,
        resultsVisibility: json['results_visibility'] as String? ?? 'admin_only',
        nominationOpenAt: json['nomination_open_at'] as String?,
        nominationCloseAt: json['nomination_close_at'] as String?,
        votingStartAt: json['voting_start_at'] as String?,
        votingEndAt: json['voting_end_at'] as String?,
        positions: (json['positions'] as List<dynamic>?)
                ?.map((p) => PositionModel.fromJson(p as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: json['created_at'] as String,
      );

  bool get isVotingActive => state == 'voting_active';
  bool get isDraft => state == 'draft';
  bool get isPublished => state == 'published';
  bool get hasResults =>
      state == 'results_provisional' || state == 'results_final';
}

class PositionModel {
  final String id;
  final String title;
  final int seatsAvailable;
  final String votingMethod;
  final int maxVotesPerVoter;
  final bool abstainAllowed;
  final bool noneOfTheAbove;
  final List<CandidateModel> candidates;

  const PositionModel({
    required this.id,
    required this.title,
    required this.seatsAvailable,
    required this.votingMethod,
    required this.maxVotesPerVoter,
    required this.abstainAllowed,
    required this.noneOfTheAbove,
    this.candidates = const [],
  });

  factory PositionModel.fromJson(Map<String, dynamic> json) => PositionModel(
        id: json['id'] as String,
        title: json['title'] as String,
        seatsAvailable: json['seats_available'] as int? ?? 1,
        votingMethod: json['voting_method'] as String? ?? 'fptp',
        maxVotesPerVoter: json['max_votes_per_voter'] as int? ?? 1,
        abstainAllowed: json['abstain_allowed'] as bool? ?? false,
        noneOfTheAbove: json['none_of_the_above'] as bool? ?? false,
        candidates: (json['candidates'] as List<dynamic>?)
                ?.map((c) => CandidateModel.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class CandidateModel {
  final String id;
  final String name;
  final String? photoUrl;
  final String manifesto;
  final String slateName;
  final String? status;
  final String? positionId;
  final String? memberId;

  const CandidateModel({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.manifesto,
    required this.slateName,
    this.status,
    this.positionId,
    this.memberId,
  });

  factory CandidateModel.fromJson(Map<String, dynamic> json) => CandidateModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? json['full_name'] as String? ?? '',
        photoUrl: json['photo_url'] as String?,
        manifesto: json['manifesto'] as String? ?? '',
        slateName: json['slate_name'] as String? ?? '',
        status: json['status'] as String?,
        positionId: json['position'] as String?,
        memberId: json['member'] as String?,
      );
}

class MemberModel {
  final String id;
  final String memberCode;
  final String fullName;
  final String email;
  final String phone;
  final String membershipStatus;
  final bool isEligibleToVote;
  final bool isEligibleToNominate;
  final String votingWeight;

  const MemberModel({
    required this.id,
    required this.memberCode,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.membershipStatus,
    required this.isEligibleToVote,
    required this.isEligibleToNominate,
    required this.votingWeight,
  });

  factory MemberModel.fromJson(Map<String, dynamic> json) => MemberModel(
        id: json['id'] as String,
        memberCode: json['member_code'] as String? ?? '',
        fullName: json['full_name'] as String,
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        membershipStatus: json['membership_status'] as String? ?? 'active',
        isEligibleToVote: json['is_eligible_to_vote'] as bool? ?? true,
        isEligibleToNominate: json['is_eligible_to_nominate'] as bool? ?? true,
        votingWeight: json['voting_weight'] as String? ?? '1.0000',
      );
}

class TallyResult {
  final String electionId;
  final String electionTitle;
  final List<PositionResult> results;

  const TallyResult({
    required this.electionId,
    required this.electionTitle,
    required this.results,
  });

  factory TallyResult.fromJson(Map<String, dynamic> json) => TallyResult(
        electionId: json['election_id'] as String,
        electionTitle: json['election_title'] as String,
        results: (json['results'] as List<dynamic>)
            .map((r) => PositionResult.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}

class PositionResult {
  final String positionId;
  final String title;
  final int totalValidBallots;
  final List<String> winners;
  final List<CandidateScore> breakdown;

  const PositionResult({
    required this.positionId,
    required this.title,
    required this.totalValidBallots,
    required this.winners,
    required this.breakdown,
  });

  factory PositionResult.fromJson(Map<String, dynamic> json) => PositionResult(
        positionId: json['position_id'] as String,
        title: json['title'] as String,
        totalValidBallots: json['total_valid_ballots'] as int? ?? 0,
        winners: (json['winners'] as List<dynamic>?)
                ?.map((w) => w as String)
                .toList() ??
            [],
        breakdown: (json['breakdown'] as List<dynamic>?)
                ?.map((b) => CandidateScore.fromJson(b as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class CandidateScore {
  final String candidateId;
  final String name;
  final double score;

  const CandidateScore({
    required this.candidateId,
    required this.name,
    required this.score,
  });

  factory CandidateScore.fromJson(Map<String, dynamic> json) => CandidateScore(
        candidateId: json['candidate_id'] as String,
        name: json['name'] as String,
        score: (json['score'] as num).toDouble(),
      );
}
