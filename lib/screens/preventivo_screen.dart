import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class PreventivoScreen extends StatefulWidget {
  final Map<String, dynamic> parqueadero;
  final List<Map<String, dynamic>> maquinas;
  const PreventivoScreen({
    super.key,
    required this.parqueadero,
    required this.maquinas,
  });

  @override
  State<PreventivoScreen> createState() => _PreventivoScreenState();
}

class _PreventivoScreenState extends State<PreventivoScreen> {
  // Para cada máquina, guardamos observaciones y fotos
  Map<String, dynamic> _datos = {};
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    for (var m in widget.maquinas) {
      _datos[m['id'].toString()] = {'observaciones': '', 'fotos': []};
    }
  }

  Future<void> _tomarFoto(String maquinaId) async {
    final picker = ImagePicker();
    final foto = await picker.pickImage(source: ImageSource.camera);
    if (foto != null) {
      final bytes = await foto.readAsBytes();
      final base64 = base64Encode(bytes);
      setState(() {
        _datos[maquinaId]['fotos'].add(base64);
      });
    }
  }

  Future<void> _guardarTodo() async {
    // Validar que todas las máquinas tengan observaciones
    for (var m in widget.maquinas) {
      if (_datos[m['id'].toString()]['observaciones'].isEmpty) {
        _mostrarMensaje('Completa las observaciones para ${m['nombre']}');
        return;
      }
    }
    setState(() => _enviando = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    // Enviar un reporte por cada máquina (o consolidado, según convenga)
    // Por simplicidad, enviamos uno por máquina
    int enviados = 0;
    for (var m in widget.maquinas) {
      final datos = _datos[m['id'].toString()];
      final response = await http.post(
        Uri.parse('$API_BASE_URL/solicitudes/crear'),
        headers: {'Authorization': 'Bearer $token'},
        body: {
          'descripcion': 'Preventivo: ${datos['observaciones']}',
          'lat': '4.6',
          'lon': '-74.0',
          'tipo': 'preventivo',
          'fotos': datos['fotos'].join(','),
          'maquina_id': m['id'].toString(),
        },
      );
      if (response.statusCode == 200) enviados++;
    }
    if (enviados == widget.maquinas.length) {
      _mostrarMensaje('Todos los reportes guardados', isError: false);
      Navigator.pop(context, true);
    } else {
      _mostrarMensaje('Error en algunos reportes');
    }
    setState(() => _enviando = false);
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
      appBar: AppBar(title: const Text('Mantenimiento Preventivo')),
      body: ListView.builder(
        itemCount: widget.maquinas.length,
        itemBuilder: (ctx, i) {
          final m = widget.maquinas[i];
          final mid = m['id'].toString();
          final datos = _datos[mid];
          return Card(
            margin: const EdgeInsets.all(8),
            child: ExpansionTile(
              title: Text(m['nombre']),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Observaciones / tareas realizadas',
                        ),
                        maxLines: 2,
                        onChanged: (val) => _datos[mid]['observaciones'] = val,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        children: datos['fotos']
                            .map<Widget>(
                              (f) => Padding(
                                padding: const EdgeInsets.all(4),
                                child: Image.memory(
                                  base64Decode(f),
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _tomarFoto(mid),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Tomar foto'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _enviando ? null : _guardarTodo,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE30613),
          ),
          child: _enviando
              ? const CircularProgressIndicator()
              : const Text('Guardar todos los reportes'),
        ),
      ),
    );
  }
}
