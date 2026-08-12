import 'dart:convert';
import 'package:http/http.dart' as http;
import 'lib/shared/models/models.dart';

void main() async {
  final resp = await http.get(Uri.parse('http://127.0.0.1:8000/api/v1/elections/75a32fe0-902e-4306-82a9-8f72a6368737/candidates/'));
  final data = jsonDecode(resp.body);
  List<dynamic> list;
  if (data is List) {
    list = data;
  } else if (data is Map && data.containsKey('results')) {
    list = data['results'] as List<dynamic>;
  } else {
    list = [];
  }
  
  final candidates = list.map((c) => CandidateModel.fromJson(c as Map<String, dynamic>)).toList();
  for (var c in candidates) {
    if (c.name.contains('at t')) {
      print('Found: ${c.name}, Endorsements: ${c.endorsements.length}');
      for (var e in c.endorsements) {
        print('- ${e.name} (${e.endorsementType})');
      }
    }
  }
}
