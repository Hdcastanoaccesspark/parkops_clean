import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class CorrectivoRemotoScreen extends StatefulWidget {
  final Map<String, dynamic> parqueadero;
  const CorrectivoRemotoScreen({super.key, required this.parqueadero});
  @override
  State<CorrectivoRemotoScreen> createState() => _CorrectivoRemotoScreenState();
}

class _CorrectivoRemotoScreenState extends State<CorrectivoRemotoScreen> {
  final _desc = TextEditingController(), _falla = TextEditingController();
  List<String> _fotosAntes = [], _fotosDespues = [], _fotosCotizacion = [];
  bool _enviando = false, _requiereCotizacion = false;
  String _cotizacionRepuesto = '';

  Future<void> _tomarFoto(String cat, bool useCamera) async {
    final source = useCamera ? ImageSource.camera : ImageSource.gallery;
    final f = await ImagePicker().pickImage(source: source);
    if (f != null) {
      final b = await f.readAsBytes();
      if (cat == 'antes')
        _fotosAntes.add(base64Encode(b));
      else if (cat == 'despues')
        _fotosDespues.add(base64Encode(b));
      else
        _fotosCotizacion.add(base64Encode(b));
      setState(() {});
    }
  }

  void _mostrarDialogoFoto(List<String> fotos, int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto'),
        content: const Text('¿Qué deseas hacer?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _mostrarFotoCompleta(fotos[index]);
            },
            child: const Text('Ver'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmarEliminarFoto(fotos, index);
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

  void _confirmarEliminarFoto(List<String> fotos, int index) {
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
              setState(() => fotos.removeAt(index));
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildFotoLista(List<String> fotos) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(fotos.length, (index) {
        return GestureDetector(
          onTap: () => _mostrarDialogoFoto(fotos, index),
          child: Image.memory(
            base64Decode(fotos[index]),
            width: 80,
            height: 80,
            fit: BoxFit.cover,
          ),
        );
      }),
    );
  }

  Future<void> _cotDialog() async {
    /* igual que en presencial, usando _buildFotoLista(_fotosCotizacion) */
  }

  Future<void> _enviar() async {
    if (_desc.text.isEmpty || _falla.text.isEmpty) {
      _msg('Completa todos los campos');
      return;
    }
    if (_fotosAntes.isEmpty) {
      _msg('Debe tomar al menos una foto del ANTES');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar reporte'),
        content: const Text('¿Confirma que desea enviar este reporte remoto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _enviando = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    const lat = 4.6, lon = -74.0;
    try {
      final res = await http.post(
        Uri.parse('$API_BASE_URL/solicitudes/crear'),
        headers: {'Authorization': 'Bearer $token'},
        body: {
          'descripcion':
              'Falla remota: ${_falla.text}\nDescripción: ${_desc.text}\nCotización: ${_requiereCotizacion ? _cotizacionRepuesto : "No"}',
          'lat': lat.toString(),
          'lon': lon.toString(),
          'tipo': 'correctivo',
          'fotos': (_fotosAntes + _fotosDespues + _fotosCotizacion).join(','),
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _msg('Reporte enviado', err: false);
        Navigator.pop(context, data['solicitud_id']);
      } else
        _msg('Error: ${res.statusCode}');
    } catch (e) {
      _msg('Error: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _msg(String m, {bool err = true}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(m),
          backgroundColor: err ? Colors.red : Colors.green,
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mantenimiento Remoto')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text(
            'Falla reportada',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextField(
            controller: _falla,
            decoration: const InputDecoration(
              hintText: 'Ej: No responde el sistema',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Descripción',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextField(
            controller: _desc,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Detalles del problema',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Fotos antes',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          _buildFotoLista(_fotosAntes),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _tomarFoto('antes', true),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Tomar foto'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _tomarFoto('antes', false),
                icon: const Icon(Icons.photo_library),
                label: const Text('Galería'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Fotos después',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          _buildFotoLista(_fotosDespues),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _tomarFoto('despues', true),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Tomar foto'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _tomarFoto('despues', false),
                icon: const Icon(Icons.photo_library),
                label: const Text('Galería'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _cotDialog,
            icon: const Icon(Icons.request_quote),
            label: Text(
              _requiereCotizacion
                  ? 'Cotización solicitada'
                  : 'Agregar cotización',
            ),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _enviando ? null : _enviar,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE30613),
              ),
              child: _enviando
                  ? const CircularProgressIndicator()
                  : const Text('Enviar reporte'),
            ),
          ),
        ],
      ),
    ),
  );
}
