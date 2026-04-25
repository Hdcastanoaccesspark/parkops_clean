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
      final response = await http.get(
        Uri.parse('$API_BASE_URL/api/solicitudes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        setState(() {
          _solicitudes = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        _mostrarError('Error al cargar solicitudes');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _mostrarError('Error de conexión');
    }
  }

  void _mostrarError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ParkOps - Cliente'),
        backgroundColor: const Color(0xFF004A99),
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
              itemBuilder: (ctx, i) => Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(_solicitudes[i]['tipo']),
                  subtitle: Text(
                    'Estado: ${_solicitudes[i]['estado']}\nDescripción: ${_solicitudes[i]['descripcion']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NuevaSolicitudScreen()),
          );
          if (result == true) {
            _cargarSolicitudes();
          }
        },
        child: const Icon(Icons.add),
        backgroundColor: const Color(0xFFE30613),
      ),
    );
  }
}

class NuevaSolicitudScreen extends StatefulWidget {
  const NuevaSolicitudScreen({super.key});

  @override
  NuevaSolicitudScreenState createState() => NuevaSolicitudScreenState();
}

class NuevaSolicitudScreenState extends State<NuevaSolicitudScreen> {
  final TextEditingController _descripcionController = TextEditingController();
  String _tipo = 'preventivo';
  final List<String> _fotos = [];
  bool _isLoading = false;

  Future<void> _tomarFoto() async {
    final picker = ImagePicker();
    final XFile? foto = await picker.pickImage(source: ImageSource.camera);
    if (foto != null) {
      final bytes = await foto.readAsBytes();
      final base64Image = base64Encode(bytes);
      setState(() => _fotos.add(base64Image));
    }
  }

  Future<void> _enviarSolicitud() async {
    if (_descripcionController.text.isEmpty) {
      _mostrarError('Escribe una descripción');
      return;
    }

    setState(() => _isLoading = true);
    Position position;
    try {
      position = await Geolocator.getCurrentPosition();
    } catch (e) {
      position =
          await Geolocator.getLastKnownPosition() ??
          Position(
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
      final response = await http.post(
        Uri.parse('$API_BASE_URL/solicitudes/crear'),
        headers: {'Authorization': 'Bearer $token'},
        body: {
          'descripcion': _descripcionController.text,
          'lat': position.latitude.toString(),
          'lon': position.longitude.toString(),
          'tipo': _tipo,
          'fotos': _fotos.join(','),
        },
      );

      if (response.statusCode == 200) {
        _mostrarError('Solicitud enviada correctamente', isError: false);
        if (mounted) Navigator.pop(context, true);
      } else {
        _mostrarError('Error al enviar solicitud');
      }
    } catch (e) {
      _mostrarError('Error de conexión');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarError(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva Solicitud'),
        backgroundColor: const Color(0xFF004A99),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _descripcionController,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(
                labelText: 'Tipo de solicitud',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'preventivo',
                  child: Text('Preventivo'),
                ),
                DropdownMenuItem(
                  value: 'correctivo',
                  child: Text('Correctivo'),
                ),
              ],
              onChanged: (value) => setState(() => _tipo = value!),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _tomarFoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Tomar foto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE30613),
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              children: _fotos
                  .map(
                    (base64Img) => Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.memory(
                        base64Decode(base64Img),
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _enviarSolicitud,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE30613),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Enviar solicitud'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
