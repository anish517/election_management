import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  // Get token first
  final loginResp = await dio.post('http://127.0.0.1:8000/api/v1/auth/login/', data: {
    'email': 'admin@gmail.com',
    'password': 'password123'
  });
  final token = loginResp.data['access'];
  
  dio.options.headers['Authorization'] = 'Bearer $token';
  
  final resp = await dio.get('http://127.0.0.1:8000/api/v1/elections/75a32fe0-902e-4306-82a9-8f72a6368737/candidates/');
  final data = resp.data;
  List<dynamic> list;
  if (data is List) {
    list = data;
  } else if (data is Map && data.containsKey('results')) {
    list = data['results'] as List<dynamic>;
  } else {
    list = [];
  }
  
  for (var c in list) {
    if (c['first_name'] == 'at' || c['name'] == 'at t') {
      print('FOUND CANDIDATE: ${c['id']}');
      print('Endorsements inside JSON:');
      print(c['endorsements']);
    }
  }
}
