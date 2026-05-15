import 'package:http/http.dart' as http;
import 'dart:convert';

const String API_BASE_URL = "http://192.168.10.109:10000";

class ApiService {
  static Future<Map<String, dynamic>?> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$API_BASE_URL/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'email': email, 'password': password},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  static Future<List<dynamic>> getSolicitudes(String token) async {
    final response = await http.get(
      Uri.parse('$API_BASE_URL/api/solicitudes'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return [];
  }

  static Future<bool> crearSolicitud(
    String token,
    Map<String, String> data,
  ) async {
    final response = await http.post(
      Uri.parse('$API_BASE_URL/solicitudes/crear'),
      headers: {'Authorization': 'Bearer $token'},
      body: data,
    );
    return response.statusCode == 200;
  }
}
