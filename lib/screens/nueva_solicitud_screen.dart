import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'dart:io';

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
      if (mounted) setState(() => _fotos.add(base64Image));
    }
  }

  Future<void> _enviarSolicitud() async {
    if (_descripcionController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Escribe una descripción')));
      return;
    }

    if (mounted) setState(() => _isLoading = true);

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
    if (token == null) {
      if (mounted) setState(() => _isLoading = false);
      _mostrarError('No hay sesión activa. Vuelve a iniciar sesión.');
      return;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$API_BASE_URL/solicitudes/crear'),
            headers: {'Authorization': 'Bearer $token'},
            body: {
              'descripcion': _descripcionController.text,
              'lat': position.latitude.toString(),
              'lon': position.longitude.toString(),
              'tipo': _tipo,
              'fotos': _fotos.join(','),
            },
          )
          .timeout(const Duration(seconds: 15));

      if (mounted) setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud enviada correctamente')),
        );
        if (mounted) Navigator.pop(context, true);
      } else {
        _mostrarError(
          'Error del servidor (${response.statusCode}): ${response.body}',
        );
      }
    } on SocketException {
      if (mounted) setState(() => _isLoading = false);
      _mostrarError('No hay conexión a internet. Verifica tu red.');
    } on http.ClientException catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _mostrarError('Error de conexión: $e');
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _mostrarError('Error inesperado: $e');
    }
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Error'),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva Solicitud')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _descripcionController,
              decoration: const InputDecoration(labelText: 'Descripción'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem(
                  value: 'preventivo',
                  child: Text('preventivo'),
                ),
                DropdownMenuItem(
                  value: 'correctivo',
                  child: Text('correctivo'),
                ),
              ],
              onChanged: (value) {
                if (value != null && mounted) setState(() => _tipo = value);
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _tomarFoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Tomar foto'),
            ),
            const SizedBox(height: 8),
            Wrap(
              children: _fotos
                  .map(
                    (fotoBase64) => Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.memory(
                        base64Decode(fotoBase64),
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
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Enviar solicitud'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
