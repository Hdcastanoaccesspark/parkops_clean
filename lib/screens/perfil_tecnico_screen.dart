import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class PerfilTecnicoScreen extends StatefulWidget {
  const PerfilTecnicoScreen({super.key});
  @override
  State<PerfilTecnicoScreen> createState() => _PerfilTecnicoScreenState();
}

class _PerfilTecnicoScreenState extends State<PerfilTecnicoScreen> {
  Map<String, dynamic>? _perfil;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final userId = prefs.getInt('userId');
    if (token == null || userId == null) return;
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/usuarios/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        setState(() {
          _perfil = jsonDecode(res.body);
          _cargando = false;
        });
      } else {
        setState(() => _cargando = false);
      }
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  Widget _buildFoto() {
    if (_perfil == null) {
      return const Icon(Icons.person, size: 50, color: Colors.grey);
    }
    final fotoStr = _perfil!['foto_perfil'] as String?;
    if (fotoStr == null || fotoStr.isEmpty) {
      return const Icon(Icons.person, size: 50, color: Colors.grey);
    }
    try {
      return ClipOval(
        child: Image.memory(
          base64Decode(fotoStr),
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.person, size: 50, color: Colors.grey),
        ),
      );
    } catch (e) {
      return const Icon(Icons.person, size: 50, color: Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mi Perfil'),
      backgroundColor: const Color(0xFF004A99),
    ),
    body: _cargando
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[300],
                  child: _buildFoto(),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.badge),
                    title: const Text('Nombre'),
                    subtitle: Text(_perfil?['nombre'] ?? ''),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.email),
                    title: const Text('Email'),
                    subtitle: Text(_perfil?['email'] ?? ''),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.health_and_safety),
                    title: const Text('EPS'),
                    subtitle: Text(_perfil?['eps'] ?? 'No registrado'),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.work),
                    title: const Text('ARL'),
                    subtitle: Text(_perfil?['arl'] ?? 'No registrado'),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.bloodtype),
                    title: const Text('RH'),
                    subtitle: Text(_perfil?['rh'] ?? 'No registrado'),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.contact_emergency),
                    title: const Text('Contacto de emergencia'),
                    subtitle: Text(
                      _perfil?['contacto_emergencia'] ?? 'No registrado',
                    ),
                  ),
                ),
              ],
            ),
          ),
  );
}
