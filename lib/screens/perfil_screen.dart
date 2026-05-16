import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/parkops_components.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});
  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  Map<String, dynamic>? _perfil;
  bool _cargando = true;
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _epsController = TextEditingController();
  final _arlController = TextEditingController();
  final _rhController = TextEditingController();
  final _contactoController = TextEditingController();
  String? _fotoPerfilBase64;

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
        final data = jsonDecode(res.body);
        setState(() {
          _perfil = data;
          _nombreController.text = data['nombre'] ?? '';
          _epsController.text = data['eps'] ?? '';
          _arlController.text = data['arl'] ?? '';
          _rhController.text = data['rh'] ?? '';
          _contactoController.text = data['contacto_emergencia'] ?? '';
          _fotoPerfilBase64 = data['foto_perfil'];
          _cargando = false;
        });
      } else {
        setState(() => _cargando = false);
      }
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  Future<void> _seleccionarFoto() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seleccionar origen'),
        content: const Text('¿De dónde quieres obtener la imagen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            child: const Text('Cámara'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const Text('Galería'),
          ),
        ],
      ),
    );
    if (source == null) return;
    final picker = ImagePicker();
    final imagen = await picker.pickImage(source: source);
    if (imagen != null) {
      final bytes = await imagen.readAsBytes();
      setState(() {
        _fotoPerfilBase64 = base64Encode(bytes);
      });
    }
  }

  Future<void> _guardarPerfil() async {
    if (!_formKey.currentState!.validate()) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final userId = prefs.getInt('userId');
    if (token == null || userId == null) return;

    try {
      final res = await http.put(
        Uri.parse('$API_BASE_URL/usuarios/$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'nombre': _nombreController.text,
          'eps': _epsController.text,
          'arl': _arlController.text,
          'rh': _rhController.text,
          'contacto_emergencia': _contactoController.text,
          'foto_perfil': _fotoPerfilBase64 ?? '',
        }),
      );
      if (res.statusCode == 200) {
        await prefs.setString('nombre', _nombreController.text);
        await prefs.setString('foto_perfil', _fotoPerfilBase64 ?? '');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil actualizado'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        throw Exception('Error al guardar');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al actualizar perfil'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        backgroundColor: AppTheme.darkSurface,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: AppTheme.darkBorder,
                          backgroundImage:
                              _fotoPerfilBase64 != null &&
                                  _fotoPerfilBase64!.isNotEmpty
                              ? MemoryImage(base64Decode(_fotoPerfilBase64!))
                              : null,
                          child:
                              (_fotoPerfilBase64 == null ||
                                  _fotoPerfilBase64!.isEmpty)
                              ? const Icon(
                                  Icons.person,
                                  size: 60,
                                  color: AppTheme.textSecondary,
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: IconButton(
                            icon: const Icon(
                              Icons.camera_alt,
                              color: AppTheme.primaryBlue,
                            ),
                            onPressed: _seleccionarFoto,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Usamos TextFormField estándar para poder usar validator
                    TextFormField(
                      controller: _nombreController,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Nombre completo',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _epsController,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'EPS',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _arlController,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'ARL',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _rhController,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'RH',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _contactoController,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Contacto de emergencia',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ParkopsPrimaryButton(
                      label: 'GUARDAR CAMBIOS',
                      onPressed: _guardarPerfil,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
