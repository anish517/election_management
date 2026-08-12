import 'package:dio/dio.dart';

void main() async {
  final d = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000/v1'));
  d.interceptors.add(LogInterceptor(requestBody: true, requestHeader: true));
  try {
    final req = await d.post('/auth/token/refresh/', data: {'refresh': 'fake'});
  } catch (e) {
    if (e is DioException) {
      print('Response: ${e.response?.data}');
    }
  }
}
