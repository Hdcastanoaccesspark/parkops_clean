import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';

class ClienteDashboard extends StatefulWidget {
  const ClienteDashboard({super.key});
  @override
  ClienteDashboardState createState() => ClienteDashboardState();
}

class ClienteDashboardState extends State<ClienteDashboard> {
  List<dynamic> _solicitudes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarSolicitudes();
  }

  Future<void> _cargarSolicitudes() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/api/solicitudes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        setState(() {
          _solicitudes = jsonDecode(res.body);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        _msg('Error al cargar solicitudes');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _msg('Error de conexión');
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Está seguro de que desea cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ParkOps - Cliente'),
      backgroundColor: const Color(0xFF004A99),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: _logout,
          tooltip: 'Cerrar sesión',
        ),
      ],
    ),
    body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _solicitudes.isEmpty
        ? const Center(
            child: Text(
              'No tienes solicitudes aún.\nPresiona el botón + para crear una.',
            ),
          )
        : ListView.builder(
            itemCount: _solicitudes.length,
            itemBuilder: (_, i) => Card(
              margin: const EdgeInsets.all(8),
              child: ListTile(
                title: Text(_solicitudes[i]['tipo']),
                subtitle: Text(
                  'Estado: ${_solicitudes[i]['estado']}\n${_solicitudes[i]['descripcion']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
              ),
            ),
          ),
    floatingActionButton: FloatingActionButton(
      onPressed: () async {
        final ok = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NuevaSolicitudScreen()),
        );
        if (ok == true) _cargarSolicitudes();
      },
      child: const Icon(Icons.add),
      backgroundColor: const Color(0xFFE30613),
    ),
  );
}

class NuevaSolicitudScreen extends StatefulWidget {
  const NuevaSolicitudScreen({super.key});
  @override
  NuevaSolicitudScreenState createState() => NuevaSolicitudScreenState();
}

class NuevaSolicitudScreenState extends State<NuevaSolicitudScreen> {
  final _desc = TextEditingController();
  String _tipo = 'preventivo';
  final List<String> _fotos = [];
  String? _videoBase64;
  bool _loading = false;

  Future<void> _tomarFoto() async {
    final p = ImagePicker();
    final f = await p.pickImage(source: ImageSource.camera);
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
        content: const Text('¿Estás seguro de que deseas eliminar esta foto?'),
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
              'tipo': _tipo,
              'fotos': _fotos.join(','),
              'videos': _videoBase64 ?? '',
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Nueva Solicitud'),
      backgroundColor: const Color(0xFF004A99),
    ),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _desc,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _tipo,
            decoration: const InputDecoration(
              labelText: 'Tipo',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'preventivo', child: Text('Preventivo')),
              DropdownMenuItem(value: 'correctivo', child: Text('Correctivo')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _tipo = v);
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _tomarFoto,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Foto'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE30613),
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            children: _fotos
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.all(4),
                    child: GestureDetector(
                      onTap: () => _mostrarDialogoFoto(entry.key),
                      child: Image.memory(
                        base64Decode(entry.value),
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _enviar,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE30613),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : const Text('Enviar solicitud'),
            ),
          ),
        ],
      ),
    ),
  );
}
