import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/parkops_components.dart';

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
      if (res.statusCode == 200)
        setState(() {
          _perfil = jsonDecode(res.body);
          _cargando = false;
        });
      else
        setState(() => _cargando = false);
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.darkBackground,
    appBar: AppBar(title: const Text('Mi Perfil')),
    body: _cargando
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: AppTheme.darkBorder,
                  child: const Icon(
                    Icons.person,
                    size: 50,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                _buildItem(Icons.badge, 'Nombre', _perfil?['nombre'] ?? ''),
                _buildItem(Icons.email, 'Email', _perfil?['email'] ?? ''),
                _buildItem(
                  Icons.health_and_safety,
                  'EPS',
                  _perfil?['eps'] ?? 'No registrado',
                ),
                _buildItem(
                  Icons.work,
                  'ARL',
                  _perfil?['arl'] ?? 'No registrado',
                ),
                _buildItem(
                  Icons.bloodtype,
                  'RH',
                  _perfil?['rh'] ?? 'No registrado',
                ),
                _buildItem(
                  Icons.contact_emergency,
                  'Contacto emergencia',
                  _perfil?['contacto_emergencia'] ?? 'No registrado',
                ),
              ],
            ),
          ),
  );

  Widget _buildItem(IconData icon, String title, String subtitle) {
    return ParkopsCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primaryBlue),
        title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}
