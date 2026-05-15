from fastapi import FastAPI, HTTPException, Depends, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, Boolean, Text, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime, timedelta, timezone
import bcrypt, jwt, math, os, traceback, base64, tempfile, urllib.request, re, qrcode
from fpdf import FPDF
from dotenv import load_dotenv
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email.mime.text import MIMEText
from email import encoders

load_dotenv()

# ----- Configuración de base de datos -----
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///parkops.db")

if DATABASE_URL.startswith("sqlite"):
    engine = create_engine(DATABASE_URL, connect_args={'check_same_thread': False})
else:
    if DATABASE_URL.startswith("postgres://"):
        DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)
    engine = create_engine(DATABASE_URL)

SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()

# ----- Modelos -----
class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True)
    email = Column(String, unique=True)
    password = Column(String)
    rol = Column(String)
    nombre = Column(String)
    lat = Column(Float, nullable=True)
    lon = Column(Float, nullable=True)
    estado = Column(String, default='libre')
    disponible = Column(Boolean, default=False)
    eps = Column(String, nullable=True)
    arl = Column(String, nullable=True)
    rh = Column(String, nullable=True)
    contacto_emergencia = Column(String, nullable=True)
    foto_perfil = Column(Text, nullable=True)
    parqueadero_id = Column(Integer, ForeignKey('parqueaderos.id'), nullable=True)

class Solicitud(Base):
    __tablename__ = 'solicitudes'
    id = Column(Integer, primary_key=True)
    cliente_id = Column(Integer)
    descripcion = Column(Text)
    lat = Column(Float)
    lon = Column(Float)
    tipo = Column(String)
    estado = Column(String)
    tecnico_id = Column(Integer, nullable=True)
    maquina_id = Column(Integer, nullable=True)
    parqueadero_id = Column(Integer, nullable=True)  # NUEVO: relación con parqueadero
    fecha_creacion = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    fecha_asignacion = Column(DateTime, nullable=True)
    fecha_aceptacion = Column(DateTime, nullable=True)
    fecha_inicio = Column(DateTime, nullable=True)
    fecha_fin = Column(DateTime, nullable=True)
    fotos = Column(Text, nullable=True)
    videos = Column(Text, nullable=True)
    items = Column(Text, nullable=True)
    firma = Column(Text, nullable=True)
    pdf_path = Column(String, nullable=True)
    origen = Column(String, default='cliente')

class Jornada(Base):
    __tablename__ = 'jornadas'
    id = Column(Integer, primary_key=True)
    tecnico_id = Column(Integer)
    inicio = Column(DateTime)
    fin = Column(DateTime, nullable=True)
    lat_inicio = Column(Float)
    lon_inicio = Column(Float)
    lat_fin = Column(Float, nullable=True)
    lon_fin = Column(Float, nullable=True)

class Parqueadero(Base):
    __tablename__ = 'parqueaderos'
    id = Column(Integer, primary_key=True)
    nombre = Column(String)
    direccion = Column(String)
    lat = Column(Float)
    lon = Column(Float)
    ciudad = Column(String)

class Maquina(Base):
    __tablename__ = 'maquinas'
    id = Column(Integer, primary_key=True)
    codigo_qr = Column(String, unique=True)
    nombre = Column(String)
    tipo = Column(String)
    parqueadero_id = Column(Integer, ForeignKey('parqueaderos.id'))
    lat = Column(Float, nullable=True)
    lon = Column(Float, nullable=True)

Base.metadata.create_all(bind=engine)

# ----- Seed de datos inicial -----
def seed_database():
    db = SessionLocal()
    try:
        if db.query(Parqueadero).count() == 0:
            p1 = Parqueadero(nombre="Parqueadero Centro", direccion="Calle 19 # 5-30", lat=4.598, lon=-74.071, ciudad="Bogotá")
            p2 = Parqueadero(nombre="Centro Comercial Unicentro", direccion="Cra 68 # 90-12", lat=4.676, lon=-74.077, ciudad="Bogotá")
            p3 = Parqueadero(nombre="Parqueadero El Dorado", direccion="Av. El Dorado", lat=4.701, lon=-74.146, ciudad="Bogotá")
            p4 = Parqueadero(nombre="Parqueadero Chapinero", direccion="Calle 45 # 15-80", lat=4.641, lon=-74.065, ciudad="Bogotá")
            p5 = Parqueadero(nombre="Parqueadero Salitre", direccion="Calle 24 # 60-10", lat=4.653, lon=-74.104, ciudad="Bogotá")
            db.add_all([p1, p2, p3, p4, p5])
            db.commit()

        if db.query(Maquina).count() == 0:
            parques = db.query(Parqueadero).all()
            parques.sort(key=lambda x: x.id)
            config = [
                {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},
                {"validador_tipo": "QR", "dispensador_tipo": "Papel"},
                {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},
                {"validador_tipo": "QR", "dispensador_tipo": "Tarjeta"},
                {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},
            ]
            maquinas = []
            for idx, p in enumerate(parques):
                i = idx + 1
                cfg = config[idx]
                maquinas.append(Maquina(codigo_qr=f"VAL_{i:03d}", nombre=f"Validador {cfg['validador_tipo']}", tipo="Validador", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"DISP_{i:03d}", nombre=f"Dispensador {cfg['dispensador_tipo']}", tipo="Dispensador", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"BAR_ENT_{i:03d}", nombre=f"Barrera Entrada {i}", tipo="Barrera", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"BAR_SAL_{i:03d}", nombre=f"Barrera Salida {i}", tipo="Barrera", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"CAM_LAT1_{i:03d}", nombre=f"Cámara Lateral 1", tipo="Camara", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"CAM_LAT2_{i:03d}", nombre=f"Cámara Lateral 2", tipo="Camara", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"CAM_PISO_{i:03d}", nombre=f"Cámara de Piso", tipo="Camara", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"LPR_ENT_{i:03d}", nombre=f"LPR Entrada {i}", tipo="LPR", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"LPR_SAL_{i:03d}", nombre=f"LPR Salida {i}", tipo="LPR", parqueadero_id=p.id))
                maquinas.append(Maquina(codigo_qr=f"CAJ_{i:03d}", nombre=f"Cajero {i}", tipo="Cajero", parqueadero_id=p.id))
            db.add_all(maquinas)
            db.commit()
    except Exception as e:
        print(f"Error seeding database: {e}")
        db.rollback()
    finally:
        db.close()

seed_database()

# ----- FastAPI app -----
app = FastAPI(title="ParkOps API")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

SECRET_KEY = "clave_super_secreta_parkops"
security = HTTPBearer()

def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=['HS256'])
        db = SessionLocal()
        user = db.query(User).filter(User.id == payload['user_id']).first()
        db.close()
        return user
    except:
        raise HTTPException(401, "Token inválido")

def distancia(lat1, lon1, lat2, lon2):
    return math.sqrt((lat1-lat2)**2 + (lon1-lon2)**2)

def generar_pdf(solicitud_id: int):
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
    if not solicitud:
        db.close()
        raise HTTPException(404, "Solicitud no encontrada")
    cliente = db.query(User).filter(User.id == solicitud.cliente_id).first()
    tecnico = db.query(User).filter(User.id == solicitud.tecnico_id).first() if solicitud.tecnico_id else None
    parqueadero = None
    if solicitud.parqueadero_id:
        parqueadero = db.query(Parqueadero).filter(Parqueadero.id == solicitud.parqueadero_id).first()
    elif solicitud.maquina_id:
        maquina = db.query(Maquina).filter(Maquina.id == solicitud.maquina_id).first()
        if maquina:
            parqueadero = db.query(Parqueadero).filter(Parqueadero.id == maquina.parqueadero_id).first()
    db.close()

    pdf = FPDF(orientation='P', unit='mm', format='A4')
    pdf.set_auto_page_break(auto=True, margin=20)
    pdf.add_page()

    azul = (0, 74, 153)
    rojo = (227, 6, 19)
    gris_claro = (240, 240, 240)
    gris_texto = (100, 100, 100)
    blanco = (255, 255, 255)

    # ---------- HEADER AZUL ----------
    pdf.set_fill_color(*azul)
    pdf.rect(0, 0, 210, 45, 'F')

    # Logo ParkOPS
    try:
        logo_url = 'https://i.imgur.com/QZhOFhX.png'
        response = urllib.request.urlopen(logo_url)
        with tempfile.NamedTemporaryFile(delete=False, suffix='.png') as tmp:
            tmp.write(response.read())
            logo_parkops_path = tmp.name
        pdf.image(logo_parkops_path, x=10, y=5, w=30)
        os.unlink(logo_parkops_path)
    except Exception as e:
        print(f"No se pudo descargar logo ParkOPS: {e}")

    # Logo Accespark (opcional)
    try:
        logo_accespark_url = 'https://i.imgur.com/WyyLdQw.png'
        response = urllib.request.urlopen(logo_accespark_url)
        with tempfile.NamedTemporaryFile(delete=False, suffix='.png') as tmp:
            tmp.write(response.read())
            logo_accespark_path = tmp.name
        pdf.image(logo_accespark_path, x=170, y=5, w=30)
        os.unlink(logo_accespark_path)
    except Exception as e:
        print(f"No se pudo descargar logo Accespark: {e}")

    # Título y metadatos
    pdf.set_y(10)
    pdf.set_x(50)
    pdf.set_font('Helvetica', 'B', 20)
    pdf.set_text_color(*blanco)
    pdf.cell(0, 10, txt='Reporte de Servicio', ln=True)
    pdf.set_x(50)
    pdf.set_font('Helvetica', '', 10)
    pdf.cell(0, 6, txt=f'ID Servicio: {solicitud_id}  |  Tipo: {solicitud.tipo}  |  Estado: {solicitud.estado}', ln=True)

    pdf.ln(20)

    # Datos generales
    pdf.set_font('Helvetica', 'B', 12)
    pdf.set_text_color(*azul)
    pdf.cell(0, 8, txt='DATOS DEL SERVICIO', ln=True)
    pdf.set_draw_color(*azul)
    pdf.line(10, pdf.get_y(), 200, pdf.get_y())
    pdf.ln(4)

    pdf.set_font('Helvetica', '', 10)
    pdf.set_text_color(0, 0, 0)
    ancho_col = 60
    def campo(label, valor):
        pdf.set_font('Helvetica', 'B', 10)
        pdf.cell(ancho_col, 7, txt=label)
        pdf.set_font('Helvetica', '', 10)
        pdf.cell(0, 7, txt=str(valor), ln=True)

    campo('Cliente:', cliente.nombre if cliente else 'N/A')
    campo('Tecnico:', tecnico.nombre if tecnico else 'N/A')
    campo('Parqueadero:', parqueadero.nombre if parqueadero else 'No especificado')
    campo('Direccion:', parqueadero.direccion if parqueadero else '')
    campo('Fecha creacion:', solicitud.fecha_creacion.strftime('%d/%m/%Y %H:%M') if solicitud.fecha_creacion else '')
    campo('Fecha cierre:', solicitud.fecha_fin.strftime('%d/%m/%Y %H:%M') if solicitud.fecha_fin else '')
    if solicitud.fecha_fin and solicitud.fecha_inicio:
        duracion = solicitud.fecha_fin - solicitud.fecha_inicio
        horas = duracion.total_seconds() / 3600
        campo('Duracion total:', f'{horas:.1f} horas')

    pdf.ln(6)

    # ---------- TIMELINE OPERATIVO ----------
    pdf.set_font('Helvetica', 'B', 12)
    pdf.set_text_color(*azul)
    pdf.cell(0, 8, txt='TRAZABILIDAD DEL SERVICIO', ln=True)
    pdf.line(10, pdf.get_y(), 200, pdf.get_y())
    pdf.ln(4)

    eventos = [
        ('Solicitud creada', solicitud.fecha_creacion),
        ('Tecnico asignado', solicitud.fecha_asignacion),
        ('Tecnico acepto', solicitud.fecha_aceptacion),
        ('Inicio de labor', solicitud.fecha_inicio),
        ('Servicio cerrado', solicitud.fecha_fin),
    ]

    pdf.set_fill_color(*azul)
    pdf.set_text_color(*blanco)
    pdf.set_font('Helvetica', 'B', 9)
    pdf.cell(90, 8, txt='Evento', border=1, fill=True)
    pdf.cell(95, 8, txt='Fecha / Hora', border=1, fill=True, ln=True)

    pdf.set_text_color(0, 0, 0)
    pdf.set_font('Helvetica', '', 9)
    fill = False
    for evento, fecha in eventos:
        if fill:
            pdf.set_fill_color(*gris_claro)
        else:
            pdf.set_fill_color(*blanco)
        fecha_str = fecha.strftime('%d/%m/%Y %H:%M') if fecha else 'Pendiente'
        pdf.cell(90, 7, txt=evento, border=1, fill=True)
        pdf.cell(95, 7, txt=fecha_str, border=1, fill=True, ln=True)
        fill = not fill

    pdf.ln(6)

    # ---------- DIAGNÓSTICO ----------
    pdf.set_font('Helvetica', 'B', 12)
    pdf.set_text_color(*azul)
    pdf.cell(0, 8, txt='DIAGNOSTICO', ln=True)
    pdf.line(10, pdf.get_y(), 200, pdf.get_y())
    pdf.ln(4)

    pdf.set_font('Helvetica', 'B', 10)
    pdf.cell(0, 7, txt='Descripcion del cliente:', ln=True)
    pdf.set_font('Helvetica', '', 10)
    pdf.multi_cell(0, 6, txt=solicitud.descripcion[:500] if solicitud.descripcion else 'Sin descripcion.')

    pdf.ln(2)
    pdf.set_font('Helvetica', 'B', 10)
    pdf.cell(0, 7, txt='Informe del tecnico:', ln=True)
    pdf.set_font('Helvetica', '', 10)
    items_text = solicitud.items if solicitud.items else 'No se registraron actividades.'
    pdf.multi_cell(0, 6, txt=items_text[:500])

    pdf.ln(6)

    # ---------- EVIDENCIAS FOTOGRÁFICAS ----------
    if solicitud.fotos:
        pdf.set_font('Helvetica', 'B', 12)
        pdf.set_text_color(*azul)
        pdf.cell(0, 8, txt='EVIDENCIAS FOTOGRAFICAS', ln=True)
        pdf.line(10, pdf.get_y(), 200, pdf.get_y())
        pdf.ln(4)

        fotos_list = [f for f in solicitud.fotos.split(',') if f]
        mitad = max(1, len(fotos_list) // 2) if len(fotos_list) > 1 else 0
        fotos_antes = fotos_list[:mitad] if mitad > 0 else fotos_list[:1]
        fotos_despues = fotos_list[mitad:] if len(fotos_list) > 1 else []
        if len(fotos_list) == 1:
            fotos_antes = fotos_list
            fotos_despues = []

        def insertar_galeria(label, lista, x_inicial, y_actual):
            if not lista:
                return y_actual
            pdf.set_font('Helvetica', 'B', 10)
            pdf.set_text_color(0,0,0)
            pdf.set_xy(x_inicial, y_actual)
            pdf.cell(0, 7, txt=label, ln=True)
            y_actual += 7
            ancho_img = 80
            alto_img = 60
            x = x_inicial
            y = y_actual
            for idx, foto_base64 in enumerate(lista[:4]):
                if idx % 2 == 0 and idx != 0:
                    x = x_inicial
                    y += alto_img + 4
                try:
                    img_bytes = base64.b64decode(foto_base64)
                    with tempfile.NamedTemporaryFile(delete=False, suffix='.jpg') as img_file:
                        img_file.write(img_bytes)
                        img_path = img_file.name
                    pdf.image(img_path, x=x, y=y, w=ancho_img, h=alto_img)
                    os.unlink(img_path)
                except Exception as e:
                    pdf.set_xy(x, y+10)
                    pdf.set_font('Helvetica', '', 8)
                    pdf.cell(ancho_img, 5, txt='Error imagen', border=0)
                x += ancho_img + 4
            return y + alto_img + 6

        y_pos = pdf.get_y()
        y_pos = insertar_galeria('ANTES', fotos_antes, 10, y_pos)
        if fotos_despues:
            y_pos += 4
            y_pos = insertar_galeria('DESPUES', fotos_despues, 10, y_pos)
        pdf.set_y(y_pos + 4)

    # ---------- COTIZACIÓN ----------
    cotizacion_texto = ''
    if solicitud.descripcion:
        match = re.search(r'Cotizaci[oó]n:\s*(.*)', solicitud.descripcion, re.IGNORECASE)
        if match:
            cotizacion_texto = match.group(1).strip()
    if cotizacion_texto:
        pdf.ln(4)
        pdf.set_font('Helvetica', 'B', 12)
        pdf.set_text_color(*azul)
        pdf.cell(0, 8, txt='COTIZACION', ln=True)
        pdf.line(10, pdf.get_y(), 200, pdf.get_y())
        pdf.ln(4)
        pdf.set_font('Helvetica', '', 10)
        pdf.multi_cell(0, 6, txt=cotizacion_texto)

    # ---------- FIRMA DIGITAL ----------
    pdf.ln(8)
    pdf.set_font('Helvetica', 'B', 12)
    pdf.set_text_color(*azul)
    pdf.cell(0, 8, txt='FIRMA DE RECIBIDO', ln=True)
    pdf.line(10, pdf.get_y(), 200, pdf.get_y())
    pdf.ln(6)

    if solicitud.firma:
        try:
            firma_bytes = base64.b64decode(solicitud.firma)
            with tempfile.NamedTemporaryFile(delete=False, suffix='.png') as firma_file:
                firma_file.write(firma_bytes)
                firma_path = firma_file.name
            pdf.image(firma_path, x=10, y=pdf.get_y(), w=60, h=30)
            os.unlink(firma_path)
            pdf.set_y(pdf.get_y() + 35)
        except Exception as e:
            pdf.set_font('Helvetica', '', 10)
            pdf.cell(0, 8, txt='Firma no disponible', ln=True)
            pdf.ln(4)
    else:
        pdf.set_font('Helvetica', '', 10)
        pdf.cell(0, 8, txt='No se registró firma digital.', ln=True)
        pdf.ln(4)

    pdf.set_font('Helvetica', 'B', 10)
    pdf.cell(0, 6, txt=f'Cliente: {cliente.nombre if cliente else ""}', ln=True)
    pdf.set_font('Helvetica', '', 10)
    pdf.cell(0, 6, txt=f'Fecha de cierre: {solicitud.fecha_fin.strftime("%d/%m/%Y %H:%M") if solicitud.fecha_fin else ""}', ln=True)

    # ---------- FOOTER CON QR ----------
    pdf.ln(10)
    try:
        qr_url = f'https://parkops-backend.onrender.com/reporte/{solicitud_id}/pdf'
        qr_img = qrcode.make(qr_url)
        with tempfile.NamedTemporaryFile(delete=False, suffix='.png') as qr_file:
            qr_img.save(qr_file.name)
            qr_path = qr_file.name
        pdf.image(qr_path, x=150, y=pdf.get_y(), w=25, h=25)
        os.unlink(qr_path)
        pdf.set_font('Helvetica', '', 7)
        pdf.set_xy(150, pdf.get_y()+26)
        pdf.cell(25, 4, txt='Validar servicio', align='C')
    except Exception as e:
        print(f"No se pudo generar QR: {e}")

    pdf.set_y(pdf.get_y() + 35)
    pdf.set_font('Helvetica', 'I', 8)
    pdf.set_text_color(*gris_texto)
    pdf.cell(0, 5, txt=f'Consecutivo: {solicitud_id}  |  Generado automaticamente por ParkOPS', align='C')
    pdf.ln(4)
    pdf.cell(0, 5, txt=f'Fecha de generacion: {datetime.now(timezone.utc).strftime("%d/%m/%Y %H:%M")}', align='C')

    pdf_path = f'/tmp/solicitud_{solicitud_id}.pdf'
    pdf.output(pdf_path)
    return pdf_path

def enviar_correo_pdf(to_email: str, pdf_path: str, solicitud_id: int):
    try:
        email_user = os.getenv("EMAIL_USER", "h.castanoaccesspark@gmail.co")
        email_pass = os.getenv("EMAIL_PASS", "")
        if not email_user or not email_pass:
            print("Credenciales de correo no configuradas")
            return

        msg = MIMEMultipart()
        msg['From'] = email_user
        msg['To'] = to_email
        msg['Subject'] = f"Reporte de servicio #{solicitud_id}"
        body = f"Adjuntamos el reporte de servicio correspondiente a su solicitud."
        msg.attach(MIMEText(body, 'plain'))

        with open(pdf_path, 'rb') as attachment:
            part = MIMEBase('application', 'pdf')
            part.set_payload(attachment.read())
            encoders.encode_base64(part)
            part.add_header('Content-Disposition', f'attachment; filename=reporte_{solicitud_id}.pdf')
            msg.attach(part)

        server = smtplib.SMTP('smtp.gmail.com', 587)
        server.starttls()
        server.login(email_user, email_pass)
        server.sendmail(email_user, to_email, msg.as_string())
        server.quit()
        print(f"Correo enviado a {to_email}")
    except Exception as e:
        print(f"Error enviando correo: {e}")

# --------------------- ENDPOINTS ------------------------
@app.get("/")
def root():
    return {"mensaje": "ParkOps API funcionando"}

@app.post("/auth/login")
def login(email: str = Form(...), password: str = Form(...)):
    db = SessionLocal()
    user = db.query(User).filter(User.email == email).first()
    db.close()
    if not user or not bcrypt.checkpw(password.encode(), user.password.encode()):
        raise HTTPException(401, "Credenciales incorrectas")
    token = jwt.encode({"user_id": user.id, "rol": user.rol, "exp": datetime.now(timezone.utc) + timedelta(hours=24)}, SECRET_KEY)
    parqueadero_id = None
    parqueadero_nombre = None
    if user.rol == 'cliente' and user.parqueadero_id is not None:
        db2 = SessionLocal()
        parqueadero = db2.query(Parqueadero).filter(Parqueadero.id == user.parqueadero_id).first()
        db2.close()
        if parqueadero:
            parqueadero_id = parqueadero.id
            parqueadero_nombre = parqueadero.nombre
    return {
        "token": token,
        "rol": user.rol,
        "user_id": user.id,
        "nombre": user.nombre,
        "parqueadero_id": parqueadero_id,
        "parqueadero_nombre": parqueadero_nombre
    }

@app.get("/usuarios/{user_id}")
def get_usuario(user_id: int, user=Depends(get_current_user)):
    if user.id != user_id and user.rol not in ['lider', 'coordinador']:
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    usuario = db.query(User).filter(User.id == user_id).first()
    db.close()
    if not usuario:
        raise HTTPException(404, "Usuario no encontrado")
    return {
        "id": usuario.id, "nombre": usuario.nombre, "email": usuario.email, "rol": usuario.rol,
        "eps": usuario.eps, "arl": usuario.arl, "rh": usuario.rh,
        "contacto_emergencia": usuario.contacto_emergencia, "foto_perfil": usuario.foto_perfil,
        "parqueadero_id": usuario.parqueadero_id
    }

@app.post("/solicitudes/crear")
def crear_solicitud(
    descripcion: str = Form(...), lat: float = Form(...), lon: float = Form(...),
    tipo: str = Form(...), fotos: str = Form(""), videos: str = Form(""),
    maquina_id: str = Form(None), user=Depends(get_current_user)):
    try:
        if user.rol not in ['cliente', 'tecnico']:
            raise HTTPException(403, "No autorizado")
        db = SessionLocal()
        origen = 'cliente' if user.rol == 'cliente' else 'tecnico'
        # Determinar parqueadero_id
        parqueadero_id = None
        if origen == 'cliente' and user.parqueadero_id:
            parqueadero_id = user.parqueadero_id
        elif maquina_id and maquina_id.strip() and maquina_id != 'None':
            try:
                maq_id = int(maquina_id)
                maquina = db.query(Maquina).filter(Maquina.id == maq_id).first()
                if maquina:
                    parqueadero_id = maquina.parqueadero_id
            except:
                pass

        tecnicos = db.query(User).filter(User.rol == 'tecnico', User.disponible == True).all()
        if tecnicos and origen == 'cliente':
            tecnico = min(tecnicos, key=lambda t: distancia(lat, lon, t.lat or 0, t.lon or 0))
            estado = 'asignada'
            fecha_asignacion = datetime.now(timezone.utc)
        else:
            tecnico = None
            estado = 'pendiente'
            fecha_asignacion = None
        maq_id = None
        if maquina_id and maquina_id.strip() and maquina_id != 'None':
            try: maq_id = int(maquina_id)
            except: pass
        solicitud = Solicitud(
            cliente_id=user.id, descripcion=descripcion, lat=lat, lon=lon, tipo=tipo,
            estado=estado, tecnico_id=tecnico.id if tecnico else None,
            maquina_id=maq_id, fecha_asignacion=fecha_asignacion,
            fotos=fotos, videos=videos, origen=origen, parqueadero_id=parqueadero_id)
        db.add(solicitud)
        db.commit()
        solicitud_id = solicitud.id
        tecnico_nombre = tecnico.nombre if tecnico else None
        db.close()
        return {"mensaje": "Solicitud creada", "tecnico": tecnico_nombre or "Pendiente de asignación", "solicitud_id": solicitud_id}
    except HTTPException:
        raise
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(500, f"Error al crear solicitud: {str(e)}")

@app.get("/api/solicitudes")
def listar_solicitudes(user=Depends(get_current_user)):
    try:
        db = SessionLocal()
        if user.rol == 'cliente':
            solicitudes = db.query(Solicitud).filter(Solicitud.cliente_id == user.id).all()
        elif user.rol == 'tecnico':
            solicitudes = db.query(Solicitud).filter(
                (Solicitud.estado == 'pendiente') |
                (Solicitud.tecnico_id == user.id) |
                (Solicitud.origen == 'tecnico')
            ).all()
        else:
            solicitudes = db.query(Solicitud).all()
        result = []
        for s in solicitudes:
            cliente_nombre = None
            parqueadero_nombre = None
            parqueadero_id = s.parqueadero_id
            if s.cliente_id:
                db2 = SessionLocal()
                cliente = db2.query(User).filter(User.id == s.cliente_id).first()
                if cliente:
                    cliente_nombre = cliente.nombre
                    if parqueadero_id is None and cliente.parqueadero_id:
                        parqueadero_id = cliente.parqueadero_id
                db2.close()
            if parqueadero_id:
                db2 = SessionLocal()
                parq = db2.query(Parqueadero).filter(Parqueadero.id == parqueadero_id).first()
                if parq:
                    parqueadero_nombre = parq.nombre
                db2.close()
            result.append({
                "id": s.id, "descripcion": s.descripcion, "estado": s.estado, "tipo": s.tipo,
                "cliente_nombre": cliente_nombre, "tecnico_id": s.tecnico_id,
                "origen": s.origen,
                "parqueadero_id": parqueadero_id,
                "parqueadero_nombre": parqueadero_nombre
            })
        db.close()
        return result
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(500, f"Error al listar solicitudes: {str(e)}")

@app.post("/tecnico/iniciar_jornada")
def iniciar_jornada(lat: float = Form(...), lon: float = Form(...), user=Depends(get_current_user)):
    try:
        if user.rol != 'tecnico': raise HTTPException(403, "No autorizado")
        db = SessionLocal()
        if db.query(Jornada).filter(Jornada.tecnico_id == user.id, Jornada.fin == None).first():
            db.close(); raise HTTPException(400, "Ya hay jornada activa")
        nueva = Jornada(tecnico_id=user.id, inicio=datetime.now(timezone.utc), lat_inicio=lat, lon_inicio=lon)
        user.disponible = True; user.lat, user.lon = lat, lon
        db.add(nueva); db.commit(); db.close()
        return {"mensaje": "Jornada iniciada"}
    except Exception as e:
        raise HTTPException(500, f"Error al iniciar jornada: {str(e)}")

@app.post("/tecnico/finalizar_jornada")
def finalizar_jornada(lat: float = Form(...), lon: float = Form(...), user=Depends(get_current_user)):
    try:
        if user.rol != 'tecnico': raise HTTPException(403, "No autorizado")
        db = SessionLocal()
        jornada = db.query(Jornada).filter(Jornada.tecnico_id == user.id, Jornada.fin == None).first()
        if not jornada: db.close(); raise HTTPException(404, "No hay jornada activa")
        jornada.fin = datetime.now(timezone.utc); jornada.lat_fin, jornada.lon_fin = lat, lon
        user.disponible = False; db.commit(); db.close()
        return {"mensaje": "Jornada finalizada"}
    except Exception as e:
        raise HTTPException(500, f"Error al finalizar jornada: {str(e)}")

@app.post("/tecnico/aceptar/{solicitud_id}")
def aceptar_solicitud(solicitud_id: int, user=Depends(get_current_user)):
    try:
        if user.rol != 'tecnico': raise HTTPException(403, "No autorizado")
        db = SessionLocal()
        solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
        if not solicitud or solicitud.estado not in ['pendiente', 'asignada']:
            db.close(); raise HTTPException(404, "Solicitud no válida")
        if solicitud.tecnico_id is not None and solicitud.tecnico_id != user.id:
            db.close(); raise HTTPException(403, "Esta solicitud ya tiene otro técnico")
        if solicitud.estado == 'pendiente':
            solicitud.tecnico_id = user.id
        solicitud.estado = 'aceptada'
        solicitud.fecha_aceptacion = datetime.now(timezone.utc)
        user.estado = 'ocupado'
        db.commit(); db.close()
        return {"mensaje": "Solicitud aceptada"}
    except Exception as e:
        raise HTTPException(500, f"Error al aceptar: {str(e)}")

@app.post("/tecnico/iniciar_servicio/{solicitud_id}")
def iniciar_servicio(solicitud_id: int, lat: float = Form(...), lon: float = Form(...), user=Depends(get_current_user)):
    try:
        if user.rol != 'tecnico': raise HTTPException(403, "No autorizado")
        db = SessionLocal()
        solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id, Solicitud.tecnico_id == user.id).first()
        if not solicitud or solicitud.estado != 'aceptada':
            db.close(); raise HTTPException(404, "Solicitud no aceptada")
        solicitud.estado = 'en_proceso'; solicitud.fecha_inicio = datetime.now(timezone.utc)
        user.estado = 'en_servicio'; db.commit(); db.close()
        return {"mensaje": "Servicio iniciado"}
    except Exception as e:
        raise HTTPException(500, f"Error al iniciar servicio: {str(e)}")

@app.post("/tecnico/cerrar_solicitud/{solicitud_id}")
def cerrar_solicitud(
    solicitud_id: int,
    items: str = Form(...),
    firma: str = Form(...),
    fotos: str = Form(""),
    user=Depends(get_current_user)
):
    try:
        if user.rol != 'tecnico':
            raise HTTPException(403, "No autorizado")
        db = SessionLocal()
        solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
        if not solicitud or solicitud.estado in ['finalizada', 'cancelada']:
            db.close()
            raise HTTPException(400, "La solicitud ya fue cerrada o cancelada")

        # Permitir cerrar si el técnico es el asignado, o si es el creador de un reporte propio
        if solicitud.tecnico_id != user.id and not (solicitud.cliente_id == user.id and solicitud.origen == 'tecnico'):
            db.close()
            raise HTTPException(403, "No tienes permiso para cerrar esta solicitud")

        # Asignar técnico si no lo tenía
        if solicitud.tecnico_id is None:
            solicitud.tecnico_id = user.id

        # Si la solicitud no tiene parqueadero_id, intentar obtenerlo de la máquina o del cliente
        if solicitud.parqueadero_id is None:
            if solicitud.maquina_id:
                maquina = db.query(Maquina).filter(Maquina.id == solicitud.maquina_id).first()
                if maquina:
                    solicitud.parqueadero_id = maquina.parqueadero_id
            else:
                cliente = db.query(User).filter(User.id == solicitud.cliente_id).first()
                if cliente and cliente.parqueadero_id:
                    solicitud.parqueadero_id = cliente.parqueadero_id

        # Preservar items original si el enviado es el genérico "Reporte completado" y ya hay items
        if items == "Reporte completado" and solicitud.items and solicitud.items != "Reporte completado":
            # No sobrescribir, mantener el diagnóstico real
            pass
        else:
            solicitud.items = items

        solicitud.estado = 'finalizada'
        solicitud.firma = firma
        if fotos:
            solicitud.fotos = fotos
        solicitud.fecha_fin = datetime.now(timezone.utc)
        user.estado = 'libre'

        try:
            pdf_path = generar_pdf(solicitud_id)
            solicitud.pdf_path = pdf_path
        except Exception as e:
            print(f"Error generando PDF: {e}")
            solicitud.pdf_path = None

        # Guardar en tabla reportes (siempre)
        db.execute("CREATE TABLE IF NOT EXISTS reportes (id SERIAL PRIMARY KEY, solicitud_id INTEGER REFERENCES solicitudes(id) ON DELETE CASCADE, pdf_url TEXT, fecha_creacion TIMESTAMPTZ DEFAULT now())")
        if solicitud.pdf_path:
            db.execute(
                "INSERT INTO reportes (solicitud_id, pdf_url) VALUES (:sid, :url)",
                {"sid": solicitud_id, "url": solicitud.pdf_path}
            )

        # Enviar correo (si hay PDF)
        if solicitud.pdf_path:
            cliente_db = db.query(User).filter(User.id == solicitud.cliente_id).first()
            if cliente_db:
                enviar_correo_pdf(cliente_db.email or "h.castanoaccesspark@gmail.co", solicitud.pdf_path, solicitud_id)

        db.commit()
        db.close()
        return {"mensaje": "Servicio finalizado, PDF generado"}
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(500, f"Error al cerrar solicitud: {str(e)}")

@app.get("/reporte/{solicitud_id}/pdf")
def descargar_pdf(solicitud_id: int, user=Depends(get_current_user)):
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
    if not solicitud:
        db.close(); raise HTTPException(404, "Solicitud no encontrada")
    if solicitud.pdf_path and os.path.exists(solicitud.pdf_path):
        db.close()
        return FileResponse(solicitud.pdf_path, media_type='application/pdf', filename=f'reporte_{solicitud_id}.pdf')
    try:
        pdf_path = generar_pdf(solicitud_id)
        solicitud.pdf_path = pdf_path
        db.execute("CREATE TABLE IF NOT EXISTS reportes (id SERIAL PRIMARY KEY, solicitud_id INTEGER REFERENCES solicitudes(id) ON DELETE CASCADE, pdf_url TEXT, fecha_creacion TIMESTAMPTZ DEFAULT now())")
        existe = db.execute("SELECT id FROM reportes WHERE solicitud_id = :sid", {"sid": solicitud_id}).first()
        if not existe:
            db.execute("INSERT INTO reportes (solicitud_id, pdf_url) VALUES (:sid, :url)", {"sid": solicitud_id, "url": pdf_path})
        db.commit(); db.close()
        return FileResponse(pdf_path, media_type='application/pdf', filename=f'reporte_{solicitud_id}.pdf')
    except Exception as e:
        db.close()
        raise HTTPException(500, f"Error al generar PDF: {str(e)}")

@app.get("/tecnicos")
def listar_tecnicos(user=Depends(get_current_user)):
    db = SessionLocal()
    tecnicos = db.query(User).filter(User.rol == 'tecnico').all()
    db.close()
    return [{"id": t.id, "nombre": t.nombre, "disponible": t.disponible, "estado": t.estado} for t in tecnicos]

@app.get("/solicitudes/{solicitud_id}")
def obtener_solicitud(solicitud_id: int, user=Depends(get_current_user)):
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
    db.close()
    if not solicitud:
        raise HTTPException(404, "Solicitud no encontrada")
    # Verificar permisos: solo el cliente, el técnico asignado o coordinador/lider
    if user.rol not in ['lider', 'coordinador'] and user.id != solicitud.cliente_id and user.id != solicitud.tecnico_id:
        raise HTTPException(403, "No autorizado")
    return {
        "id": solicitud.id,
        "descripcion": solicitud.descripcion,
        "estado": solicitud.estado,
        "fotos": solicitud.fotos,
        "items": solicitud.items,
        "firma": solicitud.firma,
        "fecha_creacion": solicitud.fecha_creacion.isoformat() if solicitud.fecha_creacion else None
    }

@app.put("/solicitudes/{solicitud_id}/asignar")
def asignar_tecnico(solicitud_id: int, tecnico_id: int = Form(...), user=Depends(get_current_user)):
    if user.rol not in ['coordinador', 'lider']:
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
    if not solicitud:
        db.close(); raise HTTPException(404, "Solicitud no encontrada")
    if solicitud.estado not in ['pendiente', 'asignada']:
        db.close(); raise HTTPException(400, "La solicitud ya fue aceptada o finalizada")
    tecnico = db.query(User).filter(User.id == tecnico_id, User.rol == 'tecnico').first()
    if not tecnico:
        db.close(); raise HTTPException(404, "Técnico no encontrado")
    solicitud.tecnico_id = tecnico_id
    solicitud.estado = 'asignada'
    solicitud.fecha_asignacion = datetime.now(timezone.utc)
    db.commit(); db.close()
    return {"mensaje": f"Solicitud asignada a {tecnico.nombre}"}

@app.put("/solicitudes/{solicitud_id}/reasignar")
def reasignar_tecnico(solicitud_id: int, nuevo_tecnico_id: int = Form(...), user=Depends(get_current_user)):
    if user.rol not in ['coordinador', 'lider']:
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
    if not solicitud:
        db.close(); raise HTTPException(404, "Solicitud no encontrada")
    if solicitud.estado in ['finalizada', 'cancelada']:
        db.close(); raise HTTPException(400, "No se puede reasignar una solicitud finalizada")
    nuevo_tec = db.query(User).filter(User.id == nuevo_tecnico_id, User.rol == 'tecnico').first()
    if not nuevo_tec:
        db.close(); raise HTTPException(404, "Técnico no encontrado")
    solicitud.tecnico_id = nuevo_tecnico_id
    solicitud.estado = 'asignada'
    solicitud.fecha_asignacion = datetime.now(timezone.utc)
    db.commit(); db.close()
    return {"mensaje": f"Solicitud reasignada a {nuevo_tec.nombre}"}

@app.post("/tecnico/devolver_a_pendiente/{solicitud_id}")
def devolver_a_pendiente(solicitud_id: int, motivo: str = Form(...), user=Depends(get_current_user)):
    if user.rol != 'tecnico':
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id, Solicitud.tecnico_id == user.id).first()
    if not solicitud or solicitud.estado != 'aceptada':
        db.close(); raise HTTPException(400, "La solicitud no está aceptada o no te pertenece")
    solicitud.estado = 'pendiente'
    db.commit(); db.close()
    return {"mensaje": "Solicitud devuelta a pendiente"}

@app.delete("/solicitudes/{solicitud_id}")
def cancelar_solicitud(solicitud_id: int, user=Depends(get_current_user)):
    if user.rol not in ['coordinador', 'lider']:
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    solicitud = db.query(Solicitud).filter(Solicitud.id == solicitud_id).first()
    if not solicitud:
        db.close(); raise HTTPException(404, "Solicitud no encontrada")
    if solicitud.estado in ['finalizada', 'cancelada']:
        db.close(); raise HTTPException(400, "No se puede cancelar una solicitud en estado final")
    solicitud.estado = 'cancelada'
    db.commit(); db.close()
    return {"mensaje": "Solicitud cancelada"}

@app.get("/parqueaderos")
def listar_parqueaderos(user=Depends(get_current_user)):
    try:
        db = SessionLocal()
        parques = db.query(Parqueadero).all()
        db.close()
        return [{"id": p.id, "nombre": p.nombre, "direccion": p.direccion, "lat": p.lat, "lon": p.lon, "ciudad": p.ciudad} for p in parques]
    except Exception as e:
        raise HTTPException(500, f"Error: {str(e)}")

@app.get("/parqueaderos/{parqueadero_id}/maquinas")
def listar_maquinas(parqueadero_id: int, user=Depends(get_current_user)):
    try:
        db = SessionLocal()
        maquinas = db.query(Maquina).filter(Maquina.parqueadero_id == parqueadero_id).all()
        db.close()
        return [{"id": m.id, "nombre": m.nombre, "tipo": m.tipo, "codigo_qr": m.codigo_qr} for m in maquinas]
    except Exception as e:
        raise HTTPException(500, f"Error: {str(e)}")

@app.get("/maquinas/qr/{codigo_qr}")
def buscar_maquina_por_qr(codigo_qr: str, user=Depends(get_current_user)):
    try:
        db = SessionLocal()
        maquina = db.query(Maquina).filter(Maquina.codigo_qr == codigo_qr).first()
        db.close()
        if not maquina: raise HTTPException(404, "Máquina no encontrada")
        return {"id": maquina.id, "nombre": maquina.nombre, "tipo": maquina.tipo, "parqueadero_id": maquina.parqueadero_id}
    except Exception as e:
        raise HTTPException(500, f"Error: {str(e)}")

@app.get("/tecnico/jornada_activa")
def jornada_activa(user=Depends(get_current_user)):
    try:
        if user.rol != 'tecnico': raise HTTPException(403)
        db = SessionLocal()
        activa = db.query(Jornada).filter(Jornada.tecnico_id == user.id, Jornada.fin == None).first()
        db.close()
        return {"activa": activa is not None}
    except Exception as e:
        raise HTTPException(500, f"Error: {str(e)}")

@app.get("/parqueaderos/{parqueadero_id}/reportes")
def reportes_por_parqueadero(parqueadero_id: int, user=Depends(get_current_user)):
    if user.rol not in ['tecnico']:
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    maquinas = db.query(Maquina).filter(Maquina.parqueadero_id == parqueadero_id).all()
    maquinas_ids = [m.id for m in maquinas]
    reportes = db.query(Solicitud).filter(
        Solicitud.estado == 'finalizada',
        Solicitud.maquina_id.in_(maquinas_ids)
    ).order_by(Solicitud.fecha_fin.desc()).all()
    db.close()
    return [{
        "id": r.id,
        "descripcion": r.descripcion,
        "fecha": r.fecha_fin,
        "tipo": r.tipo,
        "maquina_nombre": next((m.nombre for m in maquinas if m.id == r.maquina_id), "")
    } for r in reportes]

@app.get("/tecnico/mis_reportes")
def mis_reportes_tecnico(parqueadero_id: int, user=Depends(get_current_user)):
    if user.rol != 'tecnico':
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    reportes = db.query(Solicitud).filter(
        Solicitud.cliente_id == user.id,
        Solicitud.origen == 'tecnico',
        Solicitud.maquina_id.in_(
            db.query(Maquina.id).filter(Maquina.parqueadero_id == parqueadero_id)
        )
    ).order_by(Solicitud.fecha_creacion.desc()).all()
    db.close()
    return [{"id": r.id, "descripcion": r.descripcion, "estado": r.estado, "tipo": r.tipo} for r in reportes]

# NUEVO: Reportes completados para el técnico (últimos 10)
@app.get("/tecnico/mis_reportes_completados")
def mis_reportes_completados(user=Depends(get_current_user)):
    if user.rol != 'tecnico':
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    reportes = db.query(Solicitud).filter(
        (Solicitud.tecnico_id == user.id) | ((Solicitud.cliente_id == user.id) & (Solicitud.origen == 'tecnico')),
        Solicitud.estado == 'finalizada'
    ).order_by(Solicitud.fecha_fin.desc()).limit(10).all()
    resultado = []
    for r in reportes:
        parqueadero_nombre = None
        if r.parqueadero_id:
            parq = db.query(Parqueadero).filter(Parqueadero.id == r.parqueadero_id).first()
            if parq:
                parqueadero_nombre = parq.nombre
        resultado.append({
            "id": r.id,
            "descripcion": r.descripcion,
            "tipo": r.tipo,
            "fecha_fin": r.fecha_fin.isoformat() if r.fecha_fin else None,
            "parqueadero_nombre": parqueadero_nombre,
            "pdf_url": f"/reporte/{r.id}/pdf"
        })
    db.close()
    return resultado

# NUEVO: Todos los reportes para coordinador/líder
@app.get("/coordinador/todos_reportes")
def todos_reportes(user=Depends(get_current_user)):
    if user.rol not in ['coordinador', 'lider']:
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    reportes = db.query(Solicitud).filter(Solicitud.estado == 'finalizada').order_by(Solicitud.fecha_fin.desc()).all()
    resultado = []
    for r in reportes:
        tecnico = db.query(User).filter(User.id == r.tecnico_id).first()
        cliente = db.query(User).filter(User.id == r.cliente_id).first()
        parqueadero_nombre = None
        if r.parqueadero_id:
            parq = db.query(Parqueadero).filter(Parqueadero.id == r.parqueadero_id).first()
            if parq:
                parqueadero_nombre = parq.nombre
        resultado.append({
            "id": r.id,
            "descripcion": r.descripcion,
            "tipo": r.tipo,
            "fecha_fin": r.fecha_fin.isoformat() if r.fecha_fin else None,
            "tecnico_nombre": tecnico.nombre if tecnico else "No asignado",
            "cliente_nombre": cliente.nombre if cliente else "Desconocido",
            "parqueadero_nombre": parqueadero_nombre,
            "pdf_url": f"/reporte/{r.id}/pdf"
        })
    db.close()
    return resultado

@app.post("/admin/insertar_datos_prueba")
def insertar_datos_prueba(user=Depends(get_current_user)):
    if user.rol not in ["lider", "coordinador"]:
        raise HTTPException(403, "No autorizado")
    db = SessionLocal()
    db.query(Maquina).delete()
    db.query(Parqueadero).delete()
    db.commit()
    p1 = Parqueadero(nombre="Parqueadero Centro", direccion="Calle 19 # 5-30", lat=4.598, lon=-74.071, ciudad="Bogotá")
    p2 = Parqueadero(nombre="Centro Comercial Unicentro", direccion="Cra 68 # 90-12", lat=4.676, lon=-74.077, ciudad="Bogotá")
    p3 = Parqueadero(nombre="Parqueadero El Dorado", direccion="Av. El Dorado", lat=4.701, lon=-74.146, ciudad="Bogotá")
    p4 = Parqueadero(nombre="Parqueadero Chapinero", direccion="Calle 45 # 15-80", lat=4.641, lon=-74.065, ciudad="Bogotá")
    p5 = Parqueadero(nombre="Parqueadero Salitre", direccion="Calle 24 # 60-10", lat=4.653, lon=-74.104, ciudad="Bogotá")
    db.add_all([p1, p2, p3, p4, p5])
    db.commit()
    config = [
        {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},
        {"validador_tipo": "QR", "dispensador_tipo": "Papel"},
        {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},
        {"validador_tipo": "QR", "dispensador_tipo": "Tarjeta"},
        {"validador_tipo": "Tarjeta", "dispensador_tipo": "Tarjeta"},
    ]
    maquinas = []
    for idx, p in enumerate([p1, p2, p3, p4, p5]):
        i = idx + 1
        cfg = config[idx]
        maquinas.append(Maquina(codigo_qr=f"VAL_{i:03d}", nombre=f"Validador {cfg['validador_tipo']}", tipo="Validador", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"DISP_{i:03d}", nombre=f"Dispensador {cfg['dispensador_tipo']}", tipo="Dispensador", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"BAR_ENT_{i:03d}", nombre=f"Barrera Entrada {i}", tipo="Barrera", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"BAR_SAL_{i:03d}", nombre=f"Barrera Salida {i}", tipo="Barrera", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"CAM_LAT1_{i:03d}", nombre=f"Cámara Lateral 1", tipo="Camara", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"CAM_LAT2_{i:03d}", nombre=f"Cámara Lateral 2", tipo="Camara", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"CAM_PISO_{i:03d}", nombre=f"Cámara de Piso", tipo="Camara", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"LPR_ENT_{i:03d}", nombre=f"LPR Entrada {i}", tipo="LPR", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"LPR_SAL_{i:03d}", nombre=f"LPR Salida {i}", tipo="LPR", parqueadero_id=p.id))
        maquinas.append(Maquina(codigo_qr=f"CAJ_{i:03d}", nombre=f"Cajero Automático {i}", tipo="Cajero", parqueadero_id=p.id))
    db.add_all(maquinas)
    db.commit()
    num_parques = db.query(Parqueadero).count()
    num_maquinas = db.query(Maquina).count()
    db.close()
    return {"mensaje": f"Insertados {num_parques} parqueaderos y {num_maquinas} máquinas"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=10000)
