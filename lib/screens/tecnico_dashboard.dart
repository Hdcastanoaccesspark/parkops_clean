import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';
import 'menu_parqueadero.dart';

class TecnicoDashboard extends StatefulWidget {
  const TecnicoDashboard({super.key});

  @override
  TecnicoDashboardState createState() => TecnicoDashboardState();
}

class TecnicoDashboardState extends State<TecnicoDashboard> {
  bool _jornadaActiva = false;
  bool _jornadaPausada = false;
  Map<String, dynamic>? _perfil;
  bool _cargandoPerfil = true;
  List<dynamic> _visitasAsignadas = [];
  bool _cargandoVisitas = true;
  List<dynamic> _parqueaderos = [];
  bool _cargandoParqueaderos = true;
  String _vistaActual = 'ninguna';
  String? _parqueaderoLaborActivo;
  String? _errorParqueaderos;

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  Future<void> _cargarDatosIniciales() async {
    await Future.wait([
      _cargarPerfil(),
      _consultarEstadoJornada(),
      _cargarVisitasAsignadas(),
      _cargarParqueaderos(),
    ]);
  }

  Future<void> _cargarPerfil() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final userId = prefs.getInt('userId');
    if (token == null || userId == null) return;
    try {
      final response = await http.get(
        Uri.parse('$API_BASE_URL/usuarios/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        setState(() {
          _perfil = jsonDecode(response.body);
          _cargandoPerfil = false;
        });
      } else {
        setState(() => _cargandoPerfil = false);
        _mostrarError('Error al cargar perfil');
      }
    } catch (e) {
      setState(() => _cargandoPerfil = false);
      _mostrarError('Conexión fallida');
    }
  }

  Future<void> _cargarVisitasAsignadas() async {
    setState(() => _cargandoVisitas = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    try {
      final response = await http.get(
        Uri.parse('$API_BASE_URL/api/solicitudes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final todas = jsonDecode(response.body) as List;
        final asignadas = todas
            .where((s) => s['estado'] == 'asignada')
            .toList();
        setState(() {
          _visitasAsignadas = asignadas;
          _cargandoVisitas = false;
        });
      } else {
        setState(() => _cargandoVisitas = false);
        _mostrarError('Error al cargar visitas');
      }
    } catch (e) {
      setState(() => _cargandoVisitas = false);
      _mostrarError('Error de red');
    }
  }

  Future<void> _cargarParqueaderos() async {
    setState(() {
      _cargandoParqueaderos = true;
      _errorParqueaderos = null;
    });
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    try {
      final response = await http.get(
        Uri.parse('$API_BASE_URL/parqueaderos'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _parqueaderos = data;
          _cargandoParqueaderos = false;
        });
      } else {
        setState(() {
          _cargandoParqueaderos = false;
          _errorParqueaderos = 'Error del servidor (${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _cargandoParqueaderos = false;
        _errorParqueaderos = 'Error de conexión: $e';
      });
    }
  }

  void _mostrarError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _mostrarMensaje(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _aceptarSolicitud(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final response = await http.post(
      Uri.parse('$API_BASE_URL/tecnico/aceptar/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      _cargarVisitasAsignadas();
      _mostrarMensaje('Solicitud aceptada');
    } else {
      _mostrarMensaje('Error al aceptar');
    }
  }

  Future<void> _iniciarJornadaConConfirmacion() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Iniciar jornada'),
        content: const Text(
          '¿Estás seguro de que deseas iniciar la jornada laboral?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, iniciar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _iniciarJornada();
    }
  }

  Future<void> _iniciarJornada() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final position = await Geolocator.getCurrentPosition();
      final response = await http.post(
        Uri.parse('$API_BASE_URL/tecnico/iniciar_jornada'),
        headers: {'Authorization': 'Bearer $token'},
        body: {
          'lat': position.latitude.toString(),
          'lon': position.longitude.toString(),
        },
      );
      if (response.statusCode == 200) {
        if (mounted) setState(() => _jornadaActiva = true);
        _mostrarMensaje('Jornada iniciada');
      } else {
        _mostrarMensaje('Error al iniciar jornada');
      }
    } catch (e) {
      _mostrarMensaje('Error: $e');
    }
  }

  Future<void> _pausarJornada() async {
    if (mounted) setState(() => _jornadaPausada = true);
    _mostrarMensaje('Jornada pausada');
  }

  Future<void> _reanudarJornada() async {
    if (mounted) setState(() => _jornadaPausada = false);
    _mostrarMensaje('Jornada reanudada');
  }

  Future<void> _finalizarJornada() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final position = await Geolocator.getCurrentPosition();
      final response = await http.post(
        Uri.parse('$API_BASE_URL/tecnico/finalizar_jornada'),
        headers: {'Authorization': 'Bearer $token'},
        body: {
          'lat': position.latitude.toString(),
          'lon': position.longitude.toString(),
        },
      );
      if (response.statusCode == 200) {
        if (mounted)
          setState(() {
            _jornadaActiva = false;
            _jornadaPausada = false;
          });
        _mostrarMensaje('Jornada finalizada');
      } else {
        _mostrarMensaje('Error al finalizar jornada');
      }
    } catch (e) {
      _mostrarMensaje('Error: $e');
    }
  }

  Future<void> _consultarEstadoJornada() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    try {
      final response = await http.get(
        Uri.parse('$API_BASE_URL/tecnico/jornada_activa'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) setState(() => _jornadaActiva = data['activa']);
      }
    } catch (_) {}
  }

  Future<void> _iniciarLaborEnParqueadero(
    Map<String, dynamic> parqueadero,
  ) async {
    if (_parqueaderoLaborActivo != null &&
        _parqueaderoLaborActivo != parqueadero['id'].toString()) {
      final cambiar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cambiar de parqueadero'),
          content: Text(
            'Ya tienes una labor activa en otro parqueadero. ¿Deseas pausarla y cambiar a ${parqueadero['nombre']}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, cambiar'),
            ),
          ],
        ),
      );
      if (cambiar != true) return;
      setState(() {
        _parqueaderoLaborActivo = null;
      });
      _mostrarMensaje('Labor anterior pausada', isError: false);
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Iniciar labor en ${parqueadero['nombre']}'),
        content: const Text('¿Estás seguro de que deseas iniciar esta labor?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Iniciar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _parqueaderoLaborActivo = parqueadero['id'].toString();
    });
    _mostrarMensaje(
      'Labor iniciada en ${parqueadero['nombre']}',
      isError: false,
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MenuParqueaderoScreen(parqueadero: parqueadero),
      ),
    );
    _mostrarMensaje('Regresaste al dashboard', isError: false);
  }

  Future<void> _seleccionarParqueadero(Map<String, dynamic> parqueadero) async {
    if (!_jornadaActiva) {
      final iniciar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Jornada inactiva'),
          content: const Text(
            'Debes iniciar la jornada antes de poder trabajar en un parqueadero. ¿Deseas iniciarla ahora?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Iniciar jornada'),
            ),
          ],
        ),
      );
      if (iniciar == true) {
        await _iniciarJornadaConConfirmacion();
        if (_jornadaActiva) {
          await _iniciarLaborEnParqueadero(parqueadero);
        }
      }
      return;
    }
    await _iniciarLaborEnParqueadero(parqueadero);
  }

  Future<void> _atenderVisitaAsignada(Map<String, dynamic> solicitud) async {
    if (!_jornadaActiva) {
      final iniciar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Jornada inactiva'),
          content: const Text(
            'Debes iniciar la jornada antes de atender una visita asignada. ¿Deseas iniciarla ahora?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Iniciar jornada'),
            ),
          ],
        ),
      );
      if (iniciar == true) {
        await _iniciarJornadaConConfirmacion();
        if (_jornadaActiva) {
          _mostrarMensaje('Próximamente: atender visita asignada');
        }
      }
      return;
    }
    _mostrarMensaje('Próximamente: atender visita asignada');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ParkOps - Técnico'),
        backgroundColor: const Color(0xFF004A99),
        actions: [
          if (!_jornadaActiva)
            IconButton(
              icon: const Icon(Icons.play_arrow, color: Colors.white),
              onPressed: _iniciarJornadaConConfirmacion,
              tooltip: 'Iniciar jornada',
            ),
          if (_jornadaActiva && !_jornadaPausada)
            IconButton(
              icon: const Icon(Icons.pause, color: Colors.white),
              onPressed: _pausarJornada,
              tooltip: 'Pausar jornada',
            ),
          if (_jornadaActiva && _jornadaPausada)
            IconButton(
              icon: const Icon(Icons.play_arrow, color: Colors.white),
              onPressed: _reanudarJornada,
              tooltip: 'Reanudar jornada',
            ),
          if (_jornadaActiva)
            IconButton(
              icon: const Icon(Icons.stop, color: Colors.white),
              onPressed: _finalizarJornada,
              tooltip: 'Finalizar jornada',
            ),
        ],
      ),
      body: _cargandoPerfil
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Técnico: ${_perfil?['nombre'] ?? 'Cargando...'}',
                          style: const TextStyle(fontSize: 18),
                        ),
                        Text('Email: ${_perfil?['email'] ?? ''}'),
                        Text('Rol: ${_perfil?['rol'] ?? ''}'),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              setState(() => _vistaActual = 'asignadas'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _vistaActual == 'asignadas'
                                ? const Color(0xFFE30613)
                                : Colors.grey,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Visitas Asignadas'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              setState(() => _vistaActual = 'parqueaderos'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _vistaActual == 'parqueaderos'
                                ? const Color(0xFFE30613)
                                : Colors.grey,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Parqueaderos'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _vistaActual == 'asignadas'
                      ? _cargandoVisitas
                            ? const Center(child: CircularProgressIndicator())
                            : _visitasAsignadas.isEmpty
                            ? const Center(
                                child: Text('No hay visitas asignadas.'),
                              )
                            : ListView.builder(
                                itemCount: _visitasAsignadas.length,
                                itemBuilder: (ctx, i) {
                                  final s = _visitasAsignadas[i];
                                  return Card(
                                    margin: const EdgeInsets.all(8),
                                    child: ListTile(
                                      title: Text(
                                        'Cliente: ${s['cliente_nombre'] ?? 'N/D'}',
                                      ),
                                      subtitle: Text(
                                        'Tipo: ${s['tipo']}\nDescripción: ${s['descripcion']}',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ElevatedButton(
                                            onPressed: () =>
                                                _aceptarSolicitud(s['id']),
                                            child: const Text('Aceptar'),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () =>
                                                _atenderVisitaAsignada(s),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                            ),
                                            child: const Text('Atender'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              )
                      : _vistaActual == 'parqueaderos'
                      ? _cargandoParqueaderos
                            ? const Center(child: CircularProgressIndicator())
                            : _errorParqueaderos != null
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Error: $_errorParqueaderos'),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: _cargarParqueaderos,
                                      child: const Text('Reintentar'),
                                    ),
                                  ],
                                ),
                              )
                            : _parqueaderos.isEmpty
                            ? const Center(
                                child: Text(
                                  'No hay parqueaderos disponibles. Ejecuta el endpoint de inserción de datos.',
                                ),
                              )
                            : ListView.builder(
                                itemCount: _parqueaderos.length,
                                itemBuilder: (ctx, i) {
                                  final p = _parqueaderos[i];
                                  return Card(
                                    margin: const EdgeInsets.all(8),
                                    child: ListTile(
                                      title: Text(p['nombre']),
                                      subtitle: Text(p['direccion']),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => _seleccionarParqueadero(p),
                                    ),
                                  );
                                },
                              )
                      : const Center(child: Text('Selecciona una opción')),
                ),
              ],
            ),
    );
  }
}
