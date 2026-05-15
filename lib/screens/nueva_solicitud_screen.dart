import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/parkops_components.dart';

class NuevaSolicitudScreen extends StatefulWidget {
  const NuevaSolicitudScreen({super.key});
  @override
  NuevaSolicitudScreenState createState() => NuevaSolicitudScreenState();
}

class NuevaSolicitudScreenState extends State<NuevaSolicitudScreen> {
  final _desc = TextEditingController();
  final List<String> _fotos = [];
  bool _loading = false;
  List<dynamic> _maquinas = [];
  String? _maquinaSeleccionada;

  @override
  void initState() {
    super.initState();
    _cargarMaquinas();
  }

  Future<void> _cargarMaquinas() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final parqueaderoId = prefs.getInt('parqueaderoId');
    if (parqueaderoId == null) return;
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/parqueaderos/$parqueaderoId/maquinas'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        setState(() {
          _maquinas = jsonDecode(res.body);
        });
      }
    } catch (e) {
      print('Error cargando máquinas: $e');
    }
  }

  Future<void> _tomarFoto() async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera);
    if (f != null) {
      final bytes = await f.readAsBytes();
      if (mounted) setState(() => _fotos.add(base64Encode(bytes)));
    }
  }

  void _mostrarDialogoFoto(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto'),
        content: const Text('¿Qué deseas hacer?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _mostrarFotoCompleta(_fotos[index]);
            },
            child: const Text('Ver'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmarEliminarFoto(index);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _mostrarFotoCompleta(String base64) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(child: Image.memory(base64Decode(base64))),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmarEliminarFoto(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar foto'),
        content: const Text('¿Estás seguro?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _fotos.removeAt(index));
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _enviar() async {
    if (_desc.text.isEmpty) {
      _msg('Escribe una descripción');
      return;
    }
    setState(() => _loading = true);
    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition();
    } catch (_) {
      pos = Position(
        latitude: 4.6,
        longitude: -74.0,
        timestamp: DateTime.now(),
        accuracy: 10,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 10,
        headingAccuracy: 10,
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    try {
      final res = await http
          .post(
            Uri.parse('$API_BASE_URL/solicitudes/crear'),
            headers: {'Authorization': 'Bearer $token'},
            body: {
              'descripcion': _desc.text,
              'lat': pos.latitude.toString(),
              'lon': pos.longitude.toString(),
              'tipo': 'correctivo',
              'fotos': _fotos.join(','),
              'maquina_id': _maquinaSeleccionada ?? '',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        _msg('Solicitud enviada', err: false);
        if (mounted) Navigator.pop(context, true);
      } else {
        final body = jsonDecode(res.body);
        _msg('Error: ${body['detail'] ?? res.statusCode}');
      }
    } catch (e) {
      _msg('Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _msg(String m, {bool err = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: err ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(title: const Text('Nueva Solicitud')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ParkopsTextField(
              label: 'Descripción',
              controller: _desc,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _maquinaSeleccionada,
              hint: const Text(
                'Selecciona máquina (opcional)',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              dropdownColor: AppTheme.darkSurface,
              style: const TextStyle(color: AppTheme.textPrimary),
              items: _maquinas.map<DropdownMenuItem<String>>((m) {
                return DropdownMenuItem(
                  value: m['id'].toString(),
                  child: Text(m['nombre']),
                );
              }).toList(),
              onChanged: (v) => setState(() => _maquinaSeleccionada = v),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _tomarFoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Tomar foto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentRed,
                foregroundColor: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                _fotos.length,
                (index) => GestureDetector(
                  onTap: () => _mostrarDialogoFoto(index),
                  child: Image.memory(
                    base64Decode(_fotos[index]),
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const Spacer(),
            ParkopsPrimaryButton(
              label: 'Enviar solicitud',
              onPressed: _loading ? null : _enviar,
              isLoading: _loading,
            ),
          ],
        ),
      ),
    );
  }
}
