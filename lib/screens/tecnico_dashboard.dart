import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/parkops_components.dart';
import 'menu_parqueadero.dart';

class TecnicoDashboard extends StatefulWidget {
  const TecnicoDashboard({super.key});
  @override
  State<TecnicoDashboard> createState() => _TecnicoDashboardState();
}

class _TecnicoDashboardState extends State<TecnicoDashboard> {
  bool _jornadaActiva = false,
      _jornadaPausada = false,
      _cargandoJornada = false;
  List<dynamic> _parqueaderos = [], _visitasAsignadas = [];
  bool _cargandoParqueaderos = true, _cargandoVisitas = true;
  String? _errorParqueaderos, _errorVisitas;
  String? _parqueaderoLaborNombre;
  bool _laborPausada = false;
  String _vistaActual = 'parqueaderos';
  String _nombre = 'Técnico';
  String _fotoPerfil = ''; // base64 o '' para placeholder
  bool _gpsActivo = false;
  final List<String> _fotosEvidencia = []; // galería rápida

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _cargarParqueaderos();
    _cargarVisitasAsignadas();
    _consultarEstadoJornada();
    _checkGPS();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nombre = prefs.getString('nombre') ?? 'Técnico';
      _fotoPerfil = prefs.getString('foto_perfil') ?? '';
    });
  }

  Future<void> _checkGPS() async {
    try {
      await Geolocator.getCurrentPosition();
      setState(() => _gpsActivo = true);
    } catch (_) {
      setState(() => _gpsActivo = false);
    }
  }

  Future<bool> _confirmar(String titulo, String mensaje) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _logout() async {
    final confirm = await _confirmar(
      'Cerrar sesión',
      '¿Está seguro de que desea cerrar sesión?',
    );
    if (!confirm) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _consultarEstadoJornada() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/tecnico/jornada_activa'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() => _jornadaActiva = data['activa'] == true);
      }
    } catch (_) {}
  }

  Future<void> _iniciarJornada() async {
    if (!await _confirmar(
      'Iniciar jornada',
      '¿Está seguro de que desea iniciar la jornada laboral?',
    )) {
      return;
    }
    setState(() => _cargandoJornada = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final res = await http.post(
        Uri.parse('$API_BASE_URL/tecnico/iniciar_jornada'),
        headers: {'Authorization': 'Bearer $token'},
        body: {'lat': pos.latitude.toString(), 'lon': pos.longitude.toString()},
      );
      if (res.statusCode == 200) {
        setState(() => _jornadaActiva = true);
        _msg('Jornada iniciada', err: false);
      } else {
        _msg('Error al iniciar jornada: ${res.statusCode}');
      }
    } catch (e) {
      _msg('Error GPS: $e');
    } finally {
      if (mounted) setState(() => _cargandoJornada = false);
    }
  }

  Future<void> _finalizarJornada() async {
    if (!await _confirmar(
      'Finalizar jornada',
      '¿Está seguro de que desea finalizar la jornada laboral?',
    )) {
      return;
    }
    setState(() => _cargandoJornada = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final res = await http.post(
        Uri.parse('$API_BASE_URL/tecnico/finalizar_jornada'),
        headers: {'Authorization': 'Bearer $token'},
        body: {'lat': pos.latitude.toString(), 'lon': pos.longitude.toString()},
      );
      if (res.statusCode == 200) {
        setState(() {
          _jornadaActiva = false;
          _jornadaPausada = false;
          _parqueaderoLaborNombre = null;
          _laborPausada = false;
        });
        _msg('Jornada finalizada', err: false);
      } else {
        _msg('Error al finalizar jornada: ${res.statusCode}');
      }
    } catch (e) {
      _msg('Error GPS: $e');
    } finally {
      if (mounted) setState(() => _cargandoJornada = false);
    }
  }

  Future<void> _pausarJornada() async {
    if (!await _confirmar('Pausar jornada', '¿Desea pausar la jornada?')) {
      return;
    }
    setState(() {
      _jornadaPausada = true;
      if (_parqueaderoLaborNombre != null) _laborPausada = true;
    });
    _msg('Jornada pausada', err: false);
  }

  Future<void> _reanudarJornada() async {
    if (!await _confirmar('Reanudar jornada', '¿Desea reanudar la jornada?')) {
      return;
    }
    setState(() {
      _jornadaPausada = false;
      if (_parqueaderoLaborNombre != null) _laborPausada = false;
    });
    _msg('Jornada reanudada', err: false);
  }

  Future<void> _cargarParqueaderos() async {
    setState(() {
      _cargandoParqueaderos = true;
      _errorParqueaderos = null;
    });
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      setState(() {
        _cargandoParqueaderos = false;
        _errorParqueaderos = 'Sin token';
      });
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/parqueaderos'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        setState(() {
          _parqueaderos = jsonDecode(res.body);
          _cargandoParqueaderos = false;
        });
      } else {
        setState(() {
          _cargandoParqueaderos = false;
          _errorParqueaderos = 'HTTP ${res.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _cargandoParqueaderos = false;
        _errorParqueaderos = 'Error de conexión';
      });
    }
  }

  Future<void> _cargarVisitasAsignadas() async {
    setState(() {
      _cargandoVisitas = true;
      _errorVisitas = null;
    });
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      setState(() {
        _cargandoVisitas = false;
        _errorVisitas = 'Sin token';
      });
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/api/solicitudes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final todas = jsonDecode(res.body) as List;
        setState(() {
          _visitasAsignadas = todas
              .where(
                (s) =>
                    s['estado'] == 'asignada' ||
                    s['estado'] == 'pendiente' ||
                    s['estado'] == 'aceptada',
              )
              .toList();
          _cargandoVisitas = false;
        });
      } else {
        setState(() {
          _cargandoVisitas = false;
          _errorVisitas = 'HTTP ${res.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _cargandoVisitas = false;
        _errorVisitas = 'Error de conexión';
      });
    }
  }

  Future<void> _aceptarSolicitud(int id) async {
    if (!_jornadaActiva) {
      _msg('Debes iniciar jornada');
      return;
    }
    if (_jornadaPausada) {
      _msg('Jornada pausada. Reanuda primero.');
      return;
    }
    if (!await _confirmar(
      'Aceptar solicitud',
      '¿Confirma que desea aceptar esta visita?',
    )) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final res = await http.post(
      Uri.parse('$API_BASE_URL/tecnico/aceptar/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      // Guardamos el parqueadero_id antes de refrescar la lista
      int? parqueaderoId;
      for (var s in _visitasAsignadas) {
        if (s['id'] == id) {
          parqueaderoId = s['parqueadero_id'];
          break;
        }
      }
      // Si no lo encontramos en las asignadas, buscamos en parqueaderos conocidos a través del cliente
      if (parqueaderoId == null) {
        // Podríamos obtener el parqueadero desde la respuesta del endpoint de solicitudes, pero no lo tenemos aquí.
        // Como fallback, navegamos a un parqueadero por defecto o mostramos mensaje.
        _msg(
          'Solicitud aceptada, pero no se encontró el parqueadero asociado',
          err: false,
        );
        _cargarVisitasAsignadas();
        return;
      }

      _cargarVisitasAsignadas();
      _msg('Solicitud aceptada', err: false);

      // Navegar al parqueadero si está en la lista local
      if (_parqueaderos.isNotEmpty) {
        final parqueadero = _parqueaderos.firstWhere(
          (p) => p['id'] == parqueaderoId,
          orElse: () => _parqueaderos.first,
        );
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MenuParqueaderoScreen(parqueadero: parqueadero),
          ),
        );
        _cargarParqueaderos();
        _cargarVisitasAsignadas();
      } else {
        _msg('No se pudo abrir el parqueadero', err: true);
      }
    } else {
      _msg('Error al aceptar: ${res.statusCode}');
    }
  }

  Future<void> _devolverAPendiente(int id) async {
    final motivoController = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Devolver a pendiente'),
        content: TextField(
          controller: motivoController,
          decoration: const InputDecoration(hintText: 'Motivo del retraso'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, motivoController.text),
            child: const Text('Devolver'),
          ),
        ],
      ),
    );
    if (motivo == null || motivo.isEmpty) {
      _msg('Debes ingresar un motivo');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final res = await http.post(
      Uri.parse('$API_BASE_URL/tecnico/devolver_a_pendiente/$id'),
      headers: {'Authorization': 'Bearer $token'},
      body: {'motivo': motivo},
    );
    if (res.statusCode == 200) {
      _cargarVisitasAsignadas();
      _msg('Solicitud devuelta a pendiente', err: false);
    } else {
      _msg('Error al devolver: ${res.statusCode}');
    }
  }

  Future<void> _entrarAParqueadero(Map<String, dynamic> p) async {
    if (!_jornadaActiva) {
      _msg('Debes iniciar jornada primero');
      return;
    }
    if (_jornadaPausada) {
      _msg('Jornada pausada');
      return;
    }
    if (!await _confirmar(
      'Iniciar labor',
      '¿Desea iniciar labor en ${p['nombre']}?',
    )) {
      return;
    }
    try {
      await Geolocator.getCurrentPosition();
    } catch (_) {}
    setState(() {
      _parqueaderoLaborNombre = p['nombre'];
      _laborPausada = false;
    });
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MenuParqueaderoScreen(parqueadero: p)),
    );
    setState(() {
      _parqueaderoLaborNombre = null;
      _laborPausada = false;
    });
    _cargarParqueaderos();
  }

  // ACCIONES RÁPIDAS
  Future<void> _abrirWaze() async {
    final url = 'https://waze.com/ul?ll=4.598,-74.071&navigate=yes';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _llamarCliente() async {
    final url = 'tel:600123456'; // cambiar por número real
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  Future<void> _abrirServicioActual() async {
    if (_parqueaderoLaborNombre == null) {
      _msg('No hay un servicio activo');
      return;
    }
    final parqueadero = _parqueaderos.firstWhere(
      (p) => p['nombre'] == _parqueaderoLaborNombre,
      orElse: () => null,
    );
    if (parqueadero != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MenuParqueaderoScreen(parqueadero: parqueadero),
        ),
      );
      _cargarParqueaderos();
    }
  }

  // EVIDENCIAS RÁPIDAS
  Future<void> _tomarFotoEvidencia() async {
    final picker = ImagePicker();
    final foto = await picker.pickImage(source: ImageSource.camera);
    if (foto != null) {
      final bytes = await foto.readAsBytes();
      setState(() {
        _fotosEvidencia.add(base64Encode(bytes));
      });
    }
  }

  void _mostrarFotoEvidencia(String base64) {
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

  void _eliminarFotoEvidencia(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar evidencia'),
        content: const Text('¿Eliminar esta foto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _fotosEvidencia.removeAt(index));
            },
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.accentRed,
        onPressed: _tomarFotoEvidencia,
        child: const Icon(Icons.camera_alt, color: Colors.white),
      ),
      body: Column(
        children: [
          // ---------- HEADER OPERATIVO ----------
          Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.primaryBlue.withOpacity(0.4),
                  AppTheme.darkBackground,
                ],
              ),
            ),
            child: Row(
              children: [
                // Foto de perfil
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.darkBorder,
                  backgroundImage: _fotoPerfil.isNotEmpty
                      ? MemoryImage(base64Decode(_fotoPerfil))
                      : null,
                  child: _fotoPerfil.isEmpty
                      ? const Icon(Icons.person, color: AppTheme.textSecondary)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nombre,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: _jornadaActiva
                                ? AppTheme.success
                                : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _jornadaActiva ? 'En jornada' : 'Sin jornada',
                            style: TextStyle(
                              fontSize: 13,
                              color: _jornadaActiva
                                  ? AppTheme.success
                                  : AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.gps_fixed,
                            size: 14,
                            color: _gpsActivo ? AppTheme.info : AppTheme.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _gpsActivo ? 'GPS activo' : 'GPS inactivo',
                            style: TextStyle(
                              fontSize: 12,
                              color: _gpsActivo
                                  ? AppTheme.info
                                  : AppTheme.error,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: AppTheme.textSecondary),
                  onPressed: _logout,
                ),
              ],
            ),
          ),

          // ---------- BOTÓN JORNADA ----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _jornadaActiva
                ? ParkopsAccentButton(
                    label: 'FINALIZAR JORNADA',
                    icon: Icons.stop_circle_outlined,
                    onPressed: _cargandoJornada ? null : _finalizarJornada,
                  )
                : ParkopsPrimaryButton(
                    label: 'INICIAR JORNADA',
                    icon: Icons.play_circle_outline,
                    onPressed: _cargandoJornada ? null : _iniciarJornada,
                  ),
          ),

          // ---------- SERVICIO ACTUAL ----------
          if (_parqueaderoLaborNombre != null)
            ParkopsCard(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on, color: AppTheme.info, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _parqueaderoLaborNombre!,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        ParkopsStatusBadge(
                          status: _laborPausada ? 'pausada' : 'en_proceso',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _quickActionButton(Icons.map, 'Waze', _abrirWaze),
                        const SizedBox(width: 8),
                        _quickActionButton(
                          Icons.phone,
                          'Llamar',
                          _llamarCliente,
                        ),
                        const SizedBox(width: 8),
                        _quickActionButton(
                          Icons.open_in_new,
                          'Abrir',
                          _abrirServicioActual,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // ---------- GALERÍA DE EVIDENCIAS ----------
          if (_fotosEvidencia.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Evidencias rápidas',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _fotosEvidencia.length,
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => _mostrarFotoEvidencia(_fotosEvidencia[i]),
                        onLongPress: () => _eliminarFotoEvidencia(i),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                              image: MemoryImage(
                                base64Decode(_fotosEvidencia[i]),
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ---------- PESTAÑAS ----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: _buildTabButton('Visitas Asignadas', 'asignadas'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTabButton('Parqueaderos', 'parqueaderos'),
                ),
              ],
            ),
          ),

          // ---------- CONTENIDO PRINCIPAL ----------
          Expanded(
            child: _vistaActual == 'asignadas'
                ? _cargandoVisitas
                      ? const Center(child: CircularProgressIndicator())
                      : _errorVisitas != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Error: $_errorVisitas',
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _cargarVisitasAsignadas,
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        )
                      : _visitasAsignadas.isEmpty
                      ? const Center(
                          child: Text(
                            'No hay visitas asignadas.',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: _visitasAsignadas.length,
                          itemBuilder: (_, i) {
                            final s = _visitasAsignadas[i];
                            final bool puedeAceptar =
                                s['estado'] == 'asignada' ||
                                s['estado'] == 'pendiente';
                            final bool puedeDevolver =
                                s['estado'] == 'aceptada';
                            return ParkopsCard(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${s['tipo']} - ${s['estado']}',
                                            style: const TextStyle(
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          Text(
                                            s['descripcion'] ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (puedeAceptar)
                                      ParkopsPrimaryButton(
                                        label: 'Aceptar',
                                        onPressed: () =>
                                            _aceptarSolicitud(s['id']),
                                        fullWidth: false,
                                      ),
                                    if (puedeDevolver)
                                      TextButton(
                                        onPressed: () =>
                                            _devolverAPendiente(s['id']),
                                        child: const Text(
                                          'Devolver',
                                          style: TextStyle(
                                            color: AppTheme.warning,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )
                : _cargandoParqueaderos
                ? const Center(child: CircularProgressIndicator())
                : _errorParqueaderos != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Error: $_errorParqueaderos',
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
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
                      'No hay parqueaderos disponibles.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _parqueaderos.length,
                    itemBuilder: (_, i) => ParkopsCard(
                      onTap: (!_jornadaActiva || _jornadaPausada)
                          ? null
                          : () => _entrarAParqueadero(_parqueaderos[i]),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: ListTile(
                        title: Text(
                          _parqueaderos[i]['nombre'],
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
                        subtitle: Text(
                          _parqueaderos[i]['direccion'],
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionButton(IconData icon, String label, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: AppTheme.info),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppTheme.info),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  Widget _buildTabButton(String text, String vista) {
    final isActive = _vistaActual == vista;
    return ElevatedButton(
      onPressed: () => setState(() => _vistaActual = vista),
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? AppTheme.primaryBlue : AppTheme.darkSurface,
        foregroundColor: AppTheme.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
      child: Text(text, style: const TextStyle(fontSize: 14)),
    );
  }
}
