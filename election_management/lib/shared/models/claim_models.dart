class VoterClaimModel {
  final String id;
  final String electionId;
  final String claimType;
  final String claimTypeDisplay;
  final String claimantName;
  final String claimantEmail;
  final String claimantPhone;
  final String claimantCitizenshipNumber;
  final String? voterRollId;
  final String targetVoterName;
  final String description;
  final String? evidenceFile;
  final String status;
  final String statusDisplay;
  final String resolutionNotes;
  final String? resolvedByEmail;
  final DateTime? resolvedAt;
  final DateTime? createdAt;

  VoterClaimModel({
    required this.id,
    required this.electionId,
    required this.claimType,
    required this.claimTypeDisplay,
    required this.claimantName,
    required this.claimantEmail,
    required this.claimantPhone,
    required this.claimantCitizenshipNumber,
    this.voterRollId,
    required this.targetVoterName,
    required this.description,
    this.evidenceFile,
    required this.status,
    required this.statusDisplay,
    required this.resolutionNotes,
    this.resolvedByEmail,
    this.resolvedAt,
    this.createdAt,
  });

  factory VoterClaimModel.fromJson(Map<String, dynamic> json) {
    return VoterClaimModel(
      id: json['id']?.toString() ?? '',
      electionId: json['election']?.toString() ?? '',
      claimType: json['claim_type'] ?? 'omission',
      claimTypeDisplay: json['claim_type_display'] ?? 'Omission',
      claimantName: json['claimant_name'] ?? '',
      claimantEmail: json['claimant_email'] ?? '',
      claimantPhone: json['claimant_phone'] ?? '',
      claimantCitizenshipNumber: json['claimant_citizenship_number'] ?? '',
      voterRollId: json['voter_roll']?.toString(),
      targetVoterName: json['target_voter_name'] ?? '',
      description: json['description'] ?? '',
      evidenceFile: json['evidence_file'],
      status: json['status'] ?? 'pending',
      statusDisplay: json['status_display'] ?? 'Pending Review',
      resolutionNotes: json['resolution_notes'] ?? '',
      resolvedByEmail: json['resolved_by_email'],
      resolvedAt: json['resolved_at'] != null ? DateTime.tryParse(json['resolved_at']) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }
}

class CandidateObjectionModel {
  final String id;
  final String electionId;
  final String candidateId;
  final String candidateName;
  final String positionTitle;
  final String claimantName;
  final String claimantEmail;
  final String claimantPhone;
  final String claimantCitizenshipNumber;
  final String objectionReason;
  final String? evidenceFile;
  final String status;
  final String statusDisplay;
  final String resolutionNotes;
  final String? resolvedByEmail;
  final DateTime? resolvedAt;
  final DateTime? createdAt;

  CandidateObjectionModel({
    required this.id,
    required this.electionId,
    required this.candidateId,
    required this.candidateName,
    required this.positionTitle,
    required this.claimantName,
    required this.claimantEmail,
    required this.claimantPhone,
    required this.claimantCitizenshipNumber,
    required this.objectionReason,
    this.evidenceFile,
    required this.status,
    required this.statusDisplay,
    required this.resolutionNotes,
    this.resolvedByEmail,
    this.resolvedAt,
    this.createdAt,
  });

  factory CandidateObjectionModel.fromJson(Map<String, dynamic> json) {
    return CandidateObjectionModel(
      id: json['id']?.toString() ?? '',
      electionId: json['election']?.toString() ?? '',
      candidateId: json['candidate']?.toString() ?? '',
      candidateName: json['candidate_name'] ?? '',
      positionTitle: json['position_title'] ?? '',
      claimantName: json['claimant_name'] ?? '',
      claimantEmail: json['claimant_email'] ?? '',
      claimantPhone: json['claimant_phone'] ?? '',
      claimantCitizenshipNumber: json['claimant_citizenship_number'] ?? '',
      objectionReason: json['objection_reason'] ?? '',
      evidenceFile: json['evidence_file'],
      status: json['status'] ?? 'pending',
      statusDisplay: json['status_display'] ?? 'Pending Review',
      resolutionNotes: json['resolution_notes'] ?? '',
      resolvedByEmail: json['resolved_by_email'],
      resolvedAt: json['resolved_at'] != null ? DateTime.tryParse(json['resolved_at']) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }
}
