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
  final _obs = TextEditingController();
  String? _fallaSeleccionada;
  String _fallaPersonalizada = '';
  List<String> _fallasPosibles = [],
      _fotosAntes = [],
      _fotosDespues = [],
      _fotosCotizacion = [];
  bool _enviando = false, _requiereCotizacion = false;
  String _cotizacionRepuesto = '';
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
    final tipo = widget.maquina['tipo'] ?? '';
    _fallasPosibles = List.from(
      _fallasPorTipo[tipo] ?? ['Falla general', 'Sin diagnóstico'],
    )..add('Otro');
  }

  Future<void> _tomarFoto(String cat) async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera);
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
        content: const Text('¿Estás seguro de que deseas eliminar esta foto?'),
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
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cotización'),
        content: const Text('¿Requiere repuestos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
        ],
      ),
    );
    if (r == true) {
      final rep = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: const Text('Detalle'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(hintText: 'Ej: Batería'),
                  onChanged: (v) => _cotizacionRepuesto = v,
                ),
                const SizedBox(height: 8),
                _buildFotoLista(_fotosCotizacion),
                ElevatedButton.icon(
                  onPressed: () async {
                    await _tomarFoto('cotizacion');
                    setStateDialog(() {});
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Foto del repuesto'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, _cotizacionRepuesto),
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      );
      if (rep != null && rep.isNotEmpty)
        setState(() {
          _requiereCotizacion = true;
          _cotizacionRepuesto = rep;
        });
    }
  }

  Future<void> _guardar() async {
    if (_obs.text.isEmpty) {
      _msg('Escribe observaciones');
      return;
    }
    if (_fallaSeleccionada == null) {
      _msg('Selecciona falla');
      return;
    }
    String falla = _fallaSeleccionada!;
    if (falla == 'Otro') {
      if (_fallaPersonalizada.isEmpty) {
        _msg('Escribe la falla');
        return;
      }
      falla = _fallaPersonalizada;
    }
    if (_fotosAntes.isEmpty) {
      _msg('Debe tomar al menos una foto del ANTES');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar reporte'),
        content: const Text('¿Confirma que desea guardar este reporte?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
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
              'Falla: $falla\nObservaciones: ${_obs.text}\nCotización: ${_requiereCotizacion ? _cotizacionRepuesto : "No"}',
          'lat': lat.toString(),
          'lon': lon.toString(),
          'tipo': 'correctivo',
          'fotos': (_fotosAntes + _fotosDespues + _fotosCotizacion).join(','),
          'maquina_id': widget.maquina['id'].toString(),
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _msg('Reporte guardado', err: false);
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
    appBar: AppBar(title: Text('Correctivo - ${widget.maquina['nombre']}')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fotos antes',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          _buildFotoLista(_fotosAntes),
          ElevatedButton.icon(
            onPressed: () => _tomarFoto('antes'),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Tomar foto (antes)'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Fotos después',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          _buildFotoLista(_fotosDespues),
          ElevatedButton.icon(
            onPressed: () => _tomarFoto('despues'),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Tomar foto (después)'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _fallaSeleccionada,
            hint: const Text('Selecciona falla'),
            items: _fallasPosibles
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) => setState(() => _fallaSeleccionada = v),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          if (_fallaSeleccionada == 'Otro')
            TextField(
              onChanged: (v) => _fallaPersonalizada = v,
              decoration: const InputDecoration(labelText: 'Especificar falla'),
            ),
          const SizedBox(height: 16),
          const Text(
            'Observaciones',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextField(
            controller: _obs,
            maxLines: 3,
            decoration: const InputDecoration(border: OutlineInputBorder()),
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
              onPressed: _enviando ? null : _guardar,
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
