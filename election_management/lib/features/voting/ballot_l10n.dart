import 'package:flutter_riverpod/flutter_riverpod.dart';

enum BallotLanguage {
  bilingual,
  english,
  nepali,
}

final ballotLanguageProvider = StateProvider<BallotLanguage>((ref) => BallotLanguage.bilingual);

class BallotL10n {
  final BallotLanguage lang;
  const BallotL10n(this.lang);

  bool get isEnglish => lang == BallotLanguage.english;
  bool get isNepali => lang == BallotLanguage.nepali;
  bool get isBilingual => lang == BallotLanguage.bilingual;

  // Convert Arabic numerals to Devanagari numerals
  static String toNepaliDigits(dynamic input) {
    final str = input.toString();
    const englishDigits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const nepaliDigits = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];
    String result = str;
    for (int i = 0; i < englishDigits.length; i++) {
      result = result.replaceAll(englishDigits[i], nepaliDigits[i]);
    }
    return result;
  }

  String formatNumber(dynamic n) {
    if (isNepali) return toNepaliDigits(n);
    return n.toString();
  }

  // Common position designation dictionary
  static final Map<String, String> _designationTranslations = {
    'president': 'अध्यक्ष',
    'vice president': 'उपाध्यक्ष',
    'senior vice president': 'वरिष्ठ उपाध्यक्ष',
    'general secretary': 'महासचिव',
    'deputy general secretary': 'उप-महासचिव',
    'secretary': 'सचिव',
    'joint secretary': 'सह-सचिव',
    'treasurer': 'कोषाध्यक्ष',
    'joint treasurer': 'सह-कोषाध्यक्ष',
    'executive member': 'कार्यकारिणी सदस्य',
    'central committee member': 'केन्द्रीय सदस्य',
    'member': 'सदस्य',
    'board member': 'सञ्चालक समिति सदस्य',
    'auditor': 'लेखा परीक्षक',
    'chairperson': 'सभापति',
    'vice chairperson': 'उपसभापति',
  };

  String translatePositionTitle(String title) {
    final lower = title.trim().toLowerCase();
    final nepaliTitle = _designationTranslations[lower];
    if (nepaliTitle == null) return title;

    if (isEnglish) return title;
    if (isNepali) return nepaliTitle;
    return '$title ($nepaliTitle)';
  }

  // Header & AppBar
  String get secretElectronicBallot {
    if (isEnglish) return 'Secret Electronic Ballot';
    if (isNepali) return 'गोप्य विद्युतीय मतपत्र';
    return 'Secret Electronic Ballot';
  }

  String get secretElectronicBallotSub {
    if (isEnglish) return 'Secure & Authenticated Voting';
    if (isNepali) return 'सुरक्षित तथा प्रमाणीकृत मतदान';
    return 'गोप्य विद्युतीय मतपत्र';
  }

  String get officialBallotBadge {
    if (isEnglish) return 'OFFICIAL BALLOT';
    if (isNepali) return 'आधिकारिक मतपत्र';
    return 'मतपत्र — OFFICIAL BALLOT';
  }

  String get allInOneView {
    if (isEnglish) return 'All-in-One';
    if (isNepali) return 'एकै पृष्ठ';
    return 'All-in-One (एकै पृष्ठ)';
  }

  String get wizardView {
    if (isEnglish) return 'Wizard';
    if (isNepali) return 'क्रमिक';
    return 'Wizard (क्रमिक)';
  }

  String elapsedTimer(String timeStr) {
    final digits = isNepali ? toNepaliDigits(timeStr) : timeStr;
    if (isEnglish) return 'Elapsed: $digits';
    if (isNepali) return 'व्यतीत समय: $digits';
    return '⏱️ $digits';
  }

  String countdownTimer(String timeStr) {
    final digits = isNepali ? toNepaliDigits(timeStr) : timeStr;
    if (isEnglish) return 'Time Left: $digits';
    if (isNepali) return 'बाँकी समय: $digits';
    return 'Time Left: $digits';
  }

  // Voter Metadata Field Labels
  String get voterNameLabel {
    if (isEnglish) return 'VOTER NAME';
    if (isNepali) return 'मतदाताको नाम';
    return 'VOTER NAME (मतदाता)';
  }

  String get voterIdLabel {
    if (isEnglish) return 'VOTER ID';
    if (isNepali) return 'मतदाता परिचयपत्र नं.';
    return 'VOTER ID (परिचयपत्र नं.)';
  }

  String get votingDateLabel {
    if (isEnglish) return 'VOTING DATE';
    if (isNepali) return 'मतदान मिति';
    return 'VOTING DATE (मिति)';
  }

  String get votingTimeLabel {
    if (isEnglish) return 'VOTING TIME';
    if (isNepali) return 'मतदान समय';
    return 'VOTING TIME (समय)';
  }

  String get authenticatedVoter {
    if (isEnglish) return 'Authenticated Voter';
    if (isNepali) return 'प्रमाणीकृत मतदाता';
    return 'Authenticated Voter (प्रमाणीकृत)';
  }

  String get securitySealNotice {
    if (isEnglish) {
      return 'End-to-End Cryptographically Sealed Ballot • Secret & Anonymous';
    }
    if (isNepali) {
      return 'अन्त्य-देखि-अन्त्य गुप्तिकृत मतपत्र • गोप्य तथा प्रमाणीकृत विद्युतीय मतदान';
    }
    return 'End-to-End Cryptographically Sealed Ballot • Secret & Anonymous (गोप्य विद्युतीय मतदान)';
  }

  String get boycottEntireElection {
    if (isEnglish) return 'Boycott Entire Election';
    if (isNepali) return 'सम्पूर्ण निर्वाचन बहिष्कार';
    return 'Boycott Entire Election (बहिष्कार)';
  }

  // Contest instructions & Counters
  String selectionInstruction(int seats) {
    final seatsStr = formatNumber(seats);
    if (isEnglish) {
      return seats == 1 ? 'Select 1 candidate' : 'Select up to $seatsStr candidates';
    }
    if (isNepali) {
      return '$seatsStr जना उम्मेदवार छनोट गर्नुहोस्';
    }
    return 'Select $seats candidate (${toNepaliDigits(seats)} जना उम्मेदवार छनोट गर्नुहोस्)';
  }

  String selectedCounter(int selected, int max) {
    final selStr = formatNumber(selected);
    final maxStr = formatNumber(max);
    if (isEnglish) return '$selStr/$maxStr Selected';
    if (isNepali) return '$maxStr मध्ये $selStr छनोट';
    return '$selStr/$maxStr Selected';
  }

  String get viewCandidateDossier {
    if (isEnglish) return 'View Candidate Dossier';
    if (isNepali) return 'उम्मेदवारको पूर्ण विवरण हेर्नुहोस्';
    return 'View Candidate Dossier (विवरण)';
  }

  String get noApprovedCandidates {
    if (isEnglish) return 'No approved candidates listed for this position.';
    if (isNepali) return 'यस पदका लागि कुनै स्वीकृत उम्मेदवार सूचीकृत छैन।';
    return 'No approved candidates listed for this position.';
  }

  // NOTA Tile
  String get noVoteTitle {
    if (isEnglish) return 'No Vote / None of the Above (NOTA)';
    if (isNepali) return 'यस पदमा कसैलाई पनि मत दिन्न / खाली मत (NOTA)';
    return 'No Vote / None of the Above (यस पदमा कसैलाई पनि मत दिन्न / NOTA)';
  }

  String get noVoteSubtitle {
    if (isEnglish) {
      return 'I choose to abstain from casting a vote for any candidate in this specific contest.';
    }
    if (isNepali) {
      return 'यस पदमा कुनै पनि उम्मेदवारलाई मत नदिई खाली राख्न चाहन्छु।';
    }
    return 'I choose to abstain from casting a vote for any candidate in this specific contest (यस पदमा कुनै पनि उम्मेदवारलाई मत नदिई खाली राख्न चाहन्छु).';
  }

  String get abstainedBadge {
    if (isEnglish) return 'ABSTAINED';
    if (isNepali) return 'खाली मत';
    return 'ABSTAINED (खाली मत)';
  }

  String get stampVoted {
    if (isEnglish) return 'VOTED';
    if (isNepali) return 'मतदिएको';
    return 'VOTED';
  }

  // Bottom action bar
  String contestsDecidedCount(int completed, int total) {
    final compStr = formatNumber(completed);
    final totStr = formatNumber(total);
    if (isEnglish) return '$compStr of $totStr Contests Decided';
    if (isNepali) return '$totStr मध्ये $compStr पदमा निर्णय भयो';
    return '$compStr of $totStr Contests Decided';
  }

  String get reviewAndSignBallot {
    if (isEnglish) return 'Review & Sign Ballot';
    if (isNepali) return 'मतपत्र समीक्षा र हस्ताक्षर';
    return 'Review & Sign Ballot (मतपत्र समीक्षा)';
  }

  String get previousContest {
    if (isEnglish) return 'Previous Contest';
    if (isNepali) return 'अघिल्लो पद';
    return 'Previous Contest (अघिल्लो)';
  }

  String get nextContest {
    if (isEnglish) return 'Next Contest';
    if (isNepali) return 'अर्को पद';
    return 'Next Contest (अर्को)';
  }

  String contestStepProgress(int current, int total) {
    final curStr = formatNumber(current);
    final totStr = formatNumber(total);
    if (isEnglish) return 'Contest $curStr of $totStr';
    if (isNepali) return 'पद $curStr / $totStr';
    return 'Contest $curStr of $totStr';
  }

  String percentCompleted(int percent) {
    final pStr = formatNumber(percent);
    if (isEnglish) return '$pStr% Completed';
    if (isNepali) return '$pStr% सम्पन्न';
    return '$pStr% Completed';
  }
}
