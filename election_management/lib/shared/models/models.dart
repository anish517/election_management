// Data models for API responses

class UserModel {
  final String id;
  final String email;
  final String phone;
  final String fullName;
  final String photoUrl;
  final String role;
  final String roleDisplay;
  final String organization;
  final String organizationName;
  final String organizationLogoUrl;
  final String organizationCoverImageUrl;
  final bool is2faEnabled;
  final String? lastLoginAt;

  const UserModel({
    required this.id,
    required this.email,
    required this.phone,
    required this.fullName,
    required this.photoUrl,
    required this.role,
    required this.roleDisplay,
    required this.organization,
    required this.organizationName,
    required this.organizationLogoUrl,
    required this.organizationCoverImageUrl,
    required this.is2faEnabled,
    this.lastLoginAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        photoUrl: json['photo_url'] as String? ?? '',
        role: json['role'] as String,
        roleDisplay: json['role_display'] as String? ?? '',
        organization: json['organization'] as String,
        organizationName: json['organization_name'] as String? ?? '',
        organizationLogoUrl: json['organization_logo_url'] as String? ?? '',
        organizationCoverImageUrl: json['organization_cover_image_url'] as String? ?? '',
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
  // Branding
  final String prefix;
  final String logoUrl;
  final String contactNumber;
  final String primaryColor;
  final String secondaryColor;
  // State
  final String state;
  // Ballot settings
  final bool isSecretBallot;
  final bool liveTurnoutEnabled;
  final String resultsVisibility;
  // Voter list schedule
  final String? firstVoterListDate;
  final String? voterListClaimDate;
  final String? finalVoterListDate;
  // Candidacy schedule
  final String? nominationOpenAt;
  final String? nominationCloseAt;
  final String? candidacyClaimDate;
  final String? candidacyFinalDate;
  // Election schedule
  final String? votingStartAt;
  final String? votingEndAt;
  // Payment
  final bool isPaidCandidacy;
  final double nomineeCharge;
  // Positions
  final List<PositionModel> positions;
  final String createdAt;

  const ElectionModel({
    required this.id,
    required this.title,
    required this.description,
    required this.prefix,
    required this.logoUrl,
    required this.contactNumber,
    required this.primaryColor,
    required this.secondaryColor,
    required this.state,
    required this.isSecretBallot,
    required this.liveTurnoutEnabled,
    required this.resultsVisibility,
    this.firstVoterListDate,
    this.voterListClaimDate,
    this.finalVoterListDate,
    this.nominationOpenAt,
    this.nominationCloseAt,
    this.candidacyClaimDate,
    this.candidacyFinalDate,
    this.votingStartAt,
    this.votingEndAt,
    required this.isPaidCandidacy,
    required this.nomineeCharge,
    required this.positions,
    required this.createdAt,
  });

  factory ElectionModel.fromJson(Map<String, dynamic> json) => ElectionModel(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        prefix: json['prefix'] as String? ?? '',
        logoUrl: json['logo_url'] as String? ?? '',
        contactNumber: json['contact_number'] as String? ?? '',
        primaryColor: json['primary_color'] as String? ?? '#6C5CE7',
        secondaryColor: json['secondary_color'] as String? ?? '#A29BFE',
        state: json['state'] as String,
        isSecretBallot: json['is_secret_ballot'] as bool? ?? true,
        liveTurnoutEnabled: json['live_turnout_enabled'] as bool? ?? false,
        resultsVisibility: json['results_visibility'] as String? ?? 'admin_only',
        firstVoterListDate: json['first_voter_list_date'] as String?,
        voterListClaimDate: json['voter_list_claim_date'] as String?,
        finalVoterListDate: json['final_voter_list_date'] as String?,
        nominationOpenAt: json['nomination_open_at'] as String?,
        nominationCloseAt: json['nomination_close_at'] as String?,
        candidacyClaimDate: json['candidacy_claim_date'] as String?,
        candidacyFinalDate: json['candidacy_final_date'] as String?,
        votingStartAt: json['voting_start_at'] as String?,
        votingEndAt: json['voting_end_at'] as String?,
        isPaidCandidacy: json['is_paid_candidacy'] as bool? ?? false,
        nomineeCharge: double.tryParse(json['nominee_charge']?.toString() ?? '0.0') ?? 0.0,
        positions: (json['positions'] as List<dynamic>?)
                ?.map((p) => PositionModel.fromJson(p as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: json['created_at'] as String,
      );

  bool get isVotingActive => state == 'voting_open';
  bool get isDraft => state == 'draft';
  bool get isPublished => state == 'published';
  bool get hasResults =>
      state == 'results_provisional' || state == 'results_final';
}



class PositionModel {
  final String id;
  final String title;
  final int seatsAvailable;
  final String quotaName;
  final String bgColor;
  final int resultOrder;
  final double nomineeCharge;
  final String votingMethod;
  final int maxVotesPerVoter;
  final bool abstainAllowed;
  final bool noneOfTheAbove;
  final List<CandidateModel> candidates;

  const PositionModel({
    required this.id,
    required this.title,
    required this.seatsAvailable,
    this.quotaName = '',
    this.bgColor = '#563d7c',
    this.resultOrder = 0,
    this.nomineeCharge = 0.0,
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
        quotaName: json['quota_name'] as String? ?? '',
        bgColor: json['bg_color'] as String? ?? '#563d7c',
        resultOrder: json['result_order'] as int? ?? 0,
        nomineeCharge: double.tryParse(json['nominee_charge']?.toString() ?? '0.0') ?? 0.0,
        votingMethod: json['voting_method'] as String? ?? 'fptp',
        maxVotesPerVoter: json['max_votes_per_voter'] as int? ?? 1,
        abstainAllowed: json['abstain_allowed'] as bool? ?? false,
        noneOfTheAbove: json['none_of_the_above'] as bool? ?? false,
        candidates: (json['candidates'] as List<dynamic>?)
                ?.map((c) => CandidateModel.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
      );
      
  bool get isFptp => votingMethod == 'fptp';
  bool get isMultiChoice => votingMethod == 'multi_choice';
  bool get isRankedChoice => votingMethod == 'ranked_choice';
  bool get isApproval => votingMethod == 'approval';
  bool get isWeighted => votingMethod == 'weighted';
  bool get isProxy => votingMethod == 'proxy';
  bool get isYesNo => votingMethod == 'yes_no';
}

class CandidateEndorsementModel {
  final String? id;
  final String endorsementType;
  final String name;
  final String citizenshipNumber;
  final String phone;
  final String membershipId;
  final String signatureUrl;

  const CandidateEndorsementModel({
    this.id,
    required this.endorsementType,
    required this.name,
    this.citizenshipNumber = '',
    this.phone = '',
    this.membershipId = '',
    this.signatureUrl = '',
  });

  factory CandidateEndorsementModel.fromJson(Map<String, dynamic> json) => CandidateEndorsementModel(
        id: json['id'] as String?,
        endorsementType: json['endorsement_type'] as String? ?? '',
        name: json['name'] as String? ?? '',
        citizenshipNumber: json['citizenship_number'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        membershipId: json['membership_id'] as String? ?? '',
        signatureUrl: json['signature_url'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'endorsement_type': endorsementType,
        'name': name,
        'citizenship_number': citizenshipNumber,
        'phone': phone,
        'membership_id': membershipId,
        'signature_url': signatureUrl,
      };
}

class CandidateModel {
  final String id;
  final String name;
  final String? photoUrl;
  final String? candidateImage;
  final String? candidateSignature;
  final String personalDescription;
  final String contributionToOrg;
  final String manifesto;
  final String slateName;
  final String? status;
  final String? positionId;
  final String? positionTitle;
  
  final String? email;
  final String? contactNumber;
  final String? gender;
  final String? dateOfBirth;
  final String? address;
  
  final String reviewNotes;
  final List<CandidateEndorsementModel> endorsements;

  const CandidateModel({
    required this.id,
    required this.name,
    this.photoUrl,
    this.candidateImage,
    this.candidateSignature,
    this.personalDescription = '',
    this.contributionToOrg = '',
    required this.manifesto,
    required this.slateName,
    this.status,
    this.positionId,
    this.positionTitle,
    this.email,
    this.contactNumber,
    this.gender,
    this.dateOfBirth,
    this.address,
    this.reviewNotes = '',
    this.endorsements = const [],
  });

  factory CandidateModel.fromJson(Map<String, dynamic> json) => CandidateModel(
        id: json['id'] as String,
        name: json['full_name'] as String? ?? json['name'] as String? ?? '',
        photoUrl: (json['photo_url'] as String?) ?? (json['candidate_image'] as String?),
        candidateImage: json['candidate_image'] as String?,
        candidateSignature: json['candidate_signature'] as String?,
        personalDescription: json['personal_description'] as String? ?? '',
        contributionToOrg: json['contribution_to_org'] as String? ?? '',
        manifesto: json['manifesto'] as String? ?? '',
        slateName: json['slate_name'] as String? ?? '',
        status: json['status'] as String?,
        positionId: json['position'] as String?,
        positionTitle: json['position_title'] as String?,
        email: json['email'] as String?,
        contactNumber: json['contact_number'] as String?,
        gender: json['gender'] as String?,
        dateOfBirth: json['date_of_birth'] as String?,
        address: json['address'] as String?,
        reviewNotes: json['review_notes'] as String? ?? '',
        endorsements: (json['endorsements'] as List<dynamic>?)
                ?.map((e) => CandidateEndorsementModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class MemberModel {
  final String id;
  final String memberCode;
  final String prefix;
  final String firstName;
  final String middleName;
  final String lastName;
  final String fullName;
  final String email;
  final String phone;
  final String membershipStatus;
  final String? membershipExpiryDate;
  final bool isEligibleToVote;
  final bool isEligibleToNominate;
  final String votingWeight;
  final String positionTitle;
  final String gender;
  final String? dateOfBirth;
  final String councilNumber;
  final String citizenshipNumber;
  final String address;
  final String department;
  final String region;
  final String photoUrl;

  const MemberModel({
    required this.id,
    required this.memberCode,
    this.prefix = '',
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    required this.fullName,
    required this.email,
    required this.phone,
    required this.membershipStatus,
    this.membershipExpiryDate,
    required this.isEligibleToVote,
    required this.isEligibleToNominate,
    required this.votingWeight,
    required this.positionTitle,
    required this.gender,
    this.dateOfBirth,
    this.councilNumber = '',
    this.citizenshipNumber = '',
    this.address = '',
    required this.department,
    required this.region,
    required this.photoUrl,
  });

      factory MemberModel.fromJson(Map<String, dynamic> json) => MemberModel(
        id: json['id'] as String,
        memberCode: json['member_code'] as String? ?? '',
        prefix: json['prefix'] as String? ?? '',
        firstName: json['first_name'] as String? ?? '',
        middleName: json['middle_name'] as String? ?? '',
        lastName: json['last_name'] as String? ?? '',
        fullName: json['full_name'] as String,
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        membershipStatus: json['membership_status'] as String? ?? 'active',
        membershipExpiryDate: json['membership_expiry_date'] as String?,
        isEligibleToVote: json['is_eligible_to_vote'] as bool? ?? true,
        isEligibleToNominate: json['is_eligible_to_nominate'] as bool? ?? true,
        votingWeight: json['voting_weight']?.toString() ?? '1.0000',
        positionTitle: json['position_title'] as String? ?? '',
        gender: json['gender'] as String? ?? '',
        dateOfBirth: json['date_of_birth'] as String?,
        councilNumber: json['council_number'] as String? ?? '',
        citizenshipNumber: json['citizenship_number'] as String? ?? '',
        address: json['address'] as String? ?? '',
        department: json['department'] as String? ?? '',
        region: json['region'] as String? ?? '',
        photoUrl: json['photo_url'] as String? ?? '',
      );
}

class TallyResult {
  final String electionId;
  final String electionTitle;
  final int totalVoters;
  final int ballotsCast;
  final double turnoutPercentage;
  final List<PositionResult> results;

  const TallyResult({
    required this.electionId,
    required this.electionTitle,
    this.totalVoters = 0,
    this.ballotsCast = 0,
    this.turnoutPercentage = 0.0,
    required this.results,
  });

  factory TallyResult.fromJson(Map<String, dynamic> json) => TallyResult(
        electionId: json['election_id'] as String,
        electionTitle: json['election_title'] as String,
        totalVoters: json['total_voters'] as int? ?? 0,
        ballotsCast: json['ballots_cast'] as int? ?? 0,
        turnoutPercentage: double.tryParse(json['turnout_percentage']?.toString() ?? '0.0') ?? 0.0,
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
  final String photoUrl;
  final double score;

  const CandidateScore({
    required this.candidateId,
    required this.name,
    required this.photoUrl,
    required this.score,
  });

  factory CandidateScore.fromJson(Map<String, dynamic> json) => CandidateScore(
        candidateId: json['candidate_id'] as String,
        name: json['name'] as String? ?? json['candidate_name'] as String? ?? '',
        photoUrl: json['photo_url'] as String? ?? '',
        score: double.tryParse(json['score']?.toString() ?? '0.0') ?? 0.0,
      );
}

class OrganizationModel {
  final String id;
  final String name;
  final String slug;
  final String prefix;
  final String orgType;
  final String councilNumber;
  final String address;
  final String phone;
  final String website;
  final String timezone;
  final String defaultLanguage;
  final String logoUrl;
  final String coverImageUrl;
  final String brandColor;
  final Map<String, dynamic> typeMetadata;
  // Bank details
  final String bankName;
  final String bankBranch;
  final String bankAccountNumber;
  final String bankAccountName;
  final String bankSwiftCode;
  final String bankQrUrl;
  final Map<String, dynamic> paymentSettings;
  // Subscription
  final String status;
  final String? trialEndsAt;
  // Election defaults
  final int grievanceWindowDays;
  final int voterRollFreezeOffsetDays;
  final int defaultNominationWindowDays;
  final int defaultVotingWindowDays;
  final int defaultSilentPeriodHours;
  final String defaultResultVisibility;
  final bool electionOfficersCanPublish;
  final int dataRetentionYears;
  final bool legalHold;

  const OrganizationModel({
    required this.id,
    required this.name,
    required this.slug,
    required this.prefix,
    required this.orgType,
    required this.councilNumber,
    required this.address,
    required this.phone,
    required this.website,
    required this.timezone,
    required this.defaultLanguage,
    required this.logoUrl,
    required this.coverImageUrl,
    required this.brandColor,
    required this.typeMetadata,
    required this.bankName,
    required this.bankBranch,
    required this.bankAccountNumber,
    required this.bankAccountName,
    required this.bankSwiftCode,
    required this.bankQrUrl,
    required this.paymentSettings,
    required this.status,
    this.trialEndsAt,
    required this.grievanceWindowDays,
    required this.voterRollFreezeOffsetDays,
    required this.defaultNominationWindowDays,
    required this.defaultVotingWindowDays,
    required this.defaultSilentPeriodHours,
    required this.defaultResultVisibility,
    required this.electionOfficersCanPublish,
    required this.dataRetentionYears,
    required this.legalHold,
  });

  factory OrganizationModel.fromJson(Map<String, dynamic> json) => OrganizationModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        prefix: json['prefix'] as String? ?? '',
        orgType: json['org_type'] as String? ?? '',
        councilNumber: json['council_number'] as String? ?? '',
        address: json['address'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        website: json['website'] as String? ?? '',
        timezone: json['timezone'] as String? ?? '',
        defaultLanguage: json['default_language'] as String? ?? '',
        logoUrl: json['logo_url'] as String? ?? '',
        coverImageUrl: json['cover_image_url'] as String? ?? '',
        brandColor: json['brand_color'] as String? ?? '',
        typeMetadata: (json['type_metadata'] as Map<String, dynamic>?) ?? {},
        bankName: json['bank_name'] as String? ?? '',
        bankBranch: json['bank_branch'] as String? ?? '',
        bankAccountNumber: json['bank_account_number'] as String? ?? '',
        bankAccountName: json['bank_account_name'] as String? ?? '',
        bankSwiftCode: json['bank_swift_code'] as String? ?? '',
        bankQrUrl: json['bank_qr_url'] as String? ?? '',
        paymentSettings: (json['payment_settings'] as Map<String, dynamic>?) ?? {},
        status: json['status'] as String? ?? '',
        trialEndsAt: json['trial_ends_at'] as String?,
        grievanceWindowDays: json['grievance_window_days'] as int? ?? 3,
        voterRollFreezeOffsetDays: json['voter_roll_freeze_offset_days'] as int? ?? 0,
        defaultNominationWindowDays: json['default_nomination_window_days'] as int? ?? 7,
        defaultVotingWindowDays: json['default_voting_window_days'] as int? ?? 1,
        defaultSilentPeriodHours: json['default_silent_period_hours'] as int? ?? 24,
        defaultResultVisibility: json['default_result_visibility'] as String? ?? 'admin_only',
        electionOfficersCanPublish: json['election_officers_can_publish'] as bool? ?? false,
        dataRetentionYears: json['data_retention_years'] as int? ?? 7,
        legalHold: json['legal_hold'] as bool? ?? false,
      );
}

class OrganizationStatsModel {
  final int totalMembers;
  final int totalElections;
  final int activeElections;
  final int totalBallotsCast;
  final double turnoutPercentage;
  final List<Map<String, dynamic>> votingProgress;
  final List<Map<String, dynamic>> resultsOverview;

  const OrganizationStatsModel({
    required this.totalMembers,
    required this.totalElections,
    required this.activeElections,
    required this.totalBallotsCast,
    required this.turnoutPercentage,
    required this.votingProgress,
    required this.resultsOverview,
  });

  factory OrganizationStatsModel.fromJson(Map<String, dynamic> json) => OrganizationStatsModel(
        totalMembers: json['total_members'] as int? ?? 0,
        totalElections: json['total_elections'] as int? ?? 0,
        activeElections: json['active_elections'] as int? ?? 0,
        totalBallotsCast: json['total_votes_cast'] as int? ?? 0,
        turnoutPercentage: double.tryParse(json['turnout_percentage']?.toString() ?? '0.0') ?? 0.0,
        votingProgress: List<Map<String, dynamic>>.from(json['voting_progress'] ?? []),
        resultsOverview: List<Map<String, dynamic>>.from(json['results_overview'] ?? []),
      );
}
