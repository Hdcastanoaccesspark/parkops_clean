import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class CorrectivoPresencialScreen extends StatefulWidget {
  final Map<String, dynamic> parqueadero;
  final Map<String, dynamic> maquina;
  const CorrectivoPresencialScreen({
    super.key,
    required this.parqueadero,
    required this.maquina,
  });

  @override
  State<CorrectivoPresencialScreen> createState() =>
      _CorrectivoPresencialScreenState();
}

class _CorrectivoPresencialScreenState
    extends State<CorrectivoPresencialScreen> {
  final TextEditingController _observacionesController =
      TextEditingController();
  String _fallaSeleccionada = '';
  List<String> _fallasPosibles = []; // se cargará según tipo de máquina
  List<String> _fotosAntes = [];
  List<String> _fotosDespues = [];
  bool _enviando = false;

  // Lista de fallas predefinidas por tipo (simplificada)
  final Map<String, List<String>> _fallasPorTipo = {
    'Barrera': ['No sube', 'No baja', 'Brazo roto', 'Lector no responde'],
    'Camara': [
      'Imagen borrosa',
      'No enciende',
      'Conexión falla',
      'Lente sucio',
    ],
    'Validador': [
      'No lee tarjeta',
      'No lee QR',
      'Pantalla apagada',
      'Error de comunicación',
    ],
    'Dispensador': [
      'No dispensa',
      'Atasco',
      'Tíquet sin cortar',
      'Error de impresión',
    ],
    'LPR': ['No reconoce placa', 'Cámara desenfocada', 'Iluminación falla'],
    'Cajero': [
      'No acepta monedas',
      'No acepta billetes',
      'Pantalla negra',
      'Atasco',
    ],
  };

  @override
  void initState() {
    super.initState();
    // Determinar fallas según el tipo de máquina
    final tipo = widget.maquina['tipo'] ?? '';
    _fallasPosibles =
        _fallasPorTipo[tipo] ?? ['Falla general', 'Sin diagnóstico'];
    _fallaSeleccionada = _fallasPosibles.first;
  }

  Future<void> _tomarFoto(String categoria) async {
    final picker = ImagePicker();
    final foto = await picker.pickImage(source: ImageSource.camera);
    if (foto != null) {
      final bytes = await foto.readAsBytes();
      final base64 = base64Encode(bytes);
      setState(() {
        if (categoria == 'antes') {
          _fotosAntes.add(base64);
        } else {
          _fotosDespues.add(base64);
        }
      });
    }
  }

  Future<void> _guardarReporte() async {
    if (_observacionesController.text.isEmpty) {
      _mostrarMensaje('Escribe las observaciones');
      return;
    }
    setState(() => _enviando = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    // Obtener ubicación actual
    // (por simplicidad usamos coordenadas por defecto)
    final lat = 4.6;
    final lon = -74.0;
    try {
      final response = await http.post(
        Uri.parse('$API_BASE_URL/solicitudes/crear'),
        headers: {'Authorization': 'Bearer $token'},
        body: {
          'descripcion':
              'Falla: $_fallaSeleccionada\nObservaciones: ${_observacionesController.text}',
          'lat': lat.toString(),
          'lon': lon.toString(),
          'tipo': 'correctivo',
          'fotos': (_fotosAntes + _fotosDespues).join(','),
          'maquina_id': widget.maquina['id'].toString(),
        },
      );
      if (response.statusCode == 200) {
        _mostrarMensaje('Reporte guardado', isError: false);
        Navigator.pop(context, true);
      } else {
        _mostrarMensaje('Error al guardar');
      }
    } catch (e) {
      _mostrarMensaje('Error de conexión');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _mostrarMensaje(String msg, {bool isError = true}) {
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
      appBar: AppBar(title: Text('Correctivo - ${widget.maquina['nombre']}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fotos antes del mantenimiento',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Wrap(
              children: _fotosAntes
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.memory(
                        base64Decode(f),
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                  .toList(),
            ),
            ElevatedButton.icon(
              onPressed: () => _tomarFoto('antes'),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Tomar foto (antes)'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Fotos después del mantenimiento',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Wrap(
              children: _fotosDespues
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.memory(
                        base64Decode(f),
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                  .toList(),
            ),
            ElevatedButton.icon(
              onPressed: () => _tomarFoto('despues'),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Tomar foto (después)'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Falla detectada',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            DropdownButtonFormField<String>(
              value: _fallaSeleccionada,
              items: _fallasPosibles
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (v) => setState(() => _fallaSeleccionada = v!),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            const Text(
              'Observaciones',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextField(
              controller: _observacionesController,
              maxLines: 3,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _enviando ? null : _guardarReporte,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE30613),
                ),
                child: _enviando
                    ? const CircularProgressIndicator()
                    : const Text('Guardar reporte'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
