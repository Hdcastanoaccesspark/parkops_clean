import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/cliente_dashboard.dart';
import 'screens/tecnico_dashboard.dart';
import 'screens/admin_dashboard.dart';
import 'config.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ParkOps',
    theme: ThemeData(primarySwatch: Colors.blue),
    initialRoute: '/login',
    routes: {
      '/login': (context) => const LoginScreen(),
      '/cliente': (context) => const ClienteDashboard(),
      '/tecnico': (context) => const TecnicoDashboard(),
      '/admin': (context) => const AdminDashboard(),
    },
    debugShowCheckedModeBanner: false,
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse('$API_BASE_URL/auth/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'email': _email.text, 'password': _pass.text},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('rol', data['rol']);
        await prefs.setInt('userId', data['user_id']);
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            data['rol'] == 'cliente'
                ? '/cliente'
                : data['rol'] == 'tecnico'
                ? '/tecnico'
                : '/admin',
          );
        }
      } else {
        if (mounted) _error('Credenciales incorrectas');
      }
    } catch (e) {
      if (mounted) _error('Error de conexión');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _error(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.network('https://i.imgur.com/dpfS4Xw.png', height: 80),
            const SizedBox(height: 20),
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña'),
            ),
            const SizedBox(height: 20),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _login,
                    child: const Text('Ingresar'),
                  ),
          ],
        ),
      ),
    ),
  );
}
