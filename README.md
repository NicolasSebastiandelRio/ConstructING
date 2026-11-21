# ConstructING - Registrando Imperios 🏛️

<img width="320" height="320" alt="constructING" src="https://github.com/user-attachments/assets/5f4d8de2-b999-4ab1-b930-c0e63154d2d7" />

> **Ecosistema de Gestión y Auditoría Técnica de Obras.**
> Reduce la asimetría de información entre el profesional y el propietario
> mediante evidencia fehaciente y transparencia técnica.

**Versión oficial:** `main` @ **`v1.0.0-mvp`** · Flutter Web + NestJS + PostgreSQL (Supabase)

---

## 🔗 Enlaces

| Recurso | Enlace |
|---|---|
| 🟢 **App en producción** (demo) | **https://constructing-three.vercel.app** |
| 🎬 **Video de presentación** (90 s · 4,29 MB) | [constructing-presentacion.mp4](https://github.com/NicolasSebastiandelRio/ConstructING/releases/download/v1.0.0-mvp/constructing-presentacion.mp4) |
| 🟢 **API** (NestJS) | https://constructing-api-production.up.railway.app |
| 📦 Release `v1.0.0-mvp` | https://github.com/NicolasSebastiandelRio/ConstructING/releases/tag/v1.0.0-mvp |
| 🚀 Guía de despliegue | [docs/DESPLIEGUE.md](docs/DESPLIEGUE.md) |
| 🎥 Pipeline del video | [video/README.md](video/README.md) |

---

## 📌 Qué es

**ConstructING** registra, certifica y audita el avance real de una obra. En vez
de depender de WhatsApp, mails y minutas en papel, cada avance queda respaldado
por **evidencia multimedia inalterable** y por la **conformidad firmada** de
ambas partes.

### El problema 🚩

En Argentina el costo de construir subió **+31,9 % interanual** (INDEC, ICC
oct-2026) mientras los presupuestos se desvían **entre 35 % y 50 %** frente al
costo real (Forbes Argentina, 2025 — datos de plataforma). Cuando aparece la
diferencia, nadie puede probar qué pasó, quién lo aprobó ni cuándo.

### La solución ✅

Una plataforma **offline-first** donde la evidencia se captura en obra con marca
de agua y checksum, los hitos se cierran con **doble firma en pantalla** y cada
acción queda en un **registro de auditoría** inalterable.

---

## ✨ Funcionalidades implementadas

| Módulo | Qué hace |
|---|---|
| **Obras y roles** | Alta, ficha técnica, estados (En planificación → En ejecución → Completado), archivado, invitación de propietario por correo |
| **Hoja de Ruta** | Hitos secuenciales, dependencias entre hitos y **ruta crítica (CPM)** con recálculo de fechas |
| **Evidencia** | Captura desde cámara **o galería**, conversión automática a JPG, **recorte y giro**, marca de agua (fecha, hito, GPS) y **checksum SHA-256** |
| **Certificación** | **Doble firma** (profesional + propietario) con trazo en pantalla, congelamiento de registros y **acta PDF** con logo y datos concisos |
| **Auditoría** | 14 acciones registradas (hitos, dependencias, obras, evidencias, firmas) con *quién / qué / cuándo / dónde* |
| **Notificaciones** | Motor de alertas con bandeja y campana para **ambos roles** (CU-67/68/69) |
| **Offline-first** | Operación sin señal y sincronización automática al recuperar red |
| **Seguridad** | Autenticación con roles, recuperación de contraseña y borrado seguro de archivos locales |

---

## 🧱 Stack implementado

| Capa | Tecnología |
|---|---|
| **Frontend** | Flutter mobile-first → entregado como **Web** (`flutter build web`) |
| **Estado** | BLoC + Clean Architecture (`features/{domain,data,presentation}`) |
| **Base local** | SQLite (IndexedDB en web) con migraciones versionadas |
| **Backend API** | NestJS + TypeORM |
| **Base de datos** | PostgreSQL gestionado en **Supabase** |
| **Deploy** | **Vercel** (frontend estático) · **Railway** (API) |

---

## 🚀 Producción

| Componente | Dónde | URL |
|---|---|---|
| Frontend | Vercel | https://constructing-three.vercel.app |
| API | Railway (`constructing-api`) | https://constructing-api-production.up.railway.app |
| Base de datos | Supabase | *(gestionada)* |

El frontend se compila con la URL de la API incrustada:

```bash
cd frontend
flutter build web --release --dart-define=API_BASE_URL=https://constructing-api-production.up.railway.app
copy vercel.json build\web\vercel.json
cd build\web && vercel deploy --prod --yes
```

> El build **debe** incluir `sqlite3.wasm` y `sqflite_sw.js`: son la base local
> del navegador. Sin ellos la app abre sin datos.
> Detalle completo en [docs/DESPLIEGUE.md](docs/DESPLIEGUE.md).

---

## 💻 Puesta en marcha local

### Backend

```bash
cd backend
npm install
npm run start:dev        # API en http://localhost:3000
```

### Frontend

```bash
cd frontend
flutter run -d chrome --web-port=8080
```

> Usá siempre el mismo `--web-port`: la caché local (IndexedDB) está atada al
> origen y con otro puerto los datos "desaparecen".

### Variables de entorno (`backend/.env`)

| Variable | Ejemplo local (Docker) | Ejemplo Supabase |
|---|---|---|
| `DB_HOST` | `localhost` | `db.xxxxx.supabase.co` |
| `DB_PORT` | `5432` | `5432` |
| `DB_USER` | `postgres` | `postgres` |
| `DB_PASSWORD` | `postgres` | *(password del proyecto)* |
| `DB_NAME` | `constructingsal` | `postgres` |
| `DB_SSL` | *(omitir)* | `true` |
| `MAIL_HOST` / `MAIL_PORT` | `smtp.ethereal.email` / `587` | ídem |
| `MAIL_USER` / `MAIL_PASS` | *(cuenta Ethereal)* | ídem |

> Los correos de Ethereal no llegan a casillas reales: se leen en
> [ethereal.email/login](https://ethereal.email/login). Ideal para probar
> bienvenida, recuperación e invitaciones sin spamear.

Alternativa con PostgreSQL local por Docker:

```bash
docker compose up -d   # PostgreSQL 16 en :5432, BD constructingsal
```

---

## 🎬 Video de presentación

Reel horizontal de **90 s** que presenta el sistema (no es una demo paso a paso).

| Requisito de la cátedra | Entrega |
|---|---|
| Presentación (no demo ni tutorial) | 8 bloques narrativos |
| Duración 1–2 minutos | **90,000 s** |
| Ancho 1024 px · H.264 · MP4 | **1024 × 576** · H.264 High · MP4 |
| Audio estéreo 44 kHz | **AAC 44,1 kHz estéreo** |
| Peso ≤ 20 MB | **4,29 MB** |
| Placa con alumno, proyecto, logo, año, materia y docente | Presente al final |

**Contenido**: dato de costo (INDEC) → pregunta → qué es ConstructING → hoja de
ruta y ruta crítica → evidencia con marca fija → doble firma y acta PDF →
auditoría y modo offline → datos del sector y placa final.

**Créditos obligatorios** (impresos en la placa): datos de INDEC
(06/11/2026 y 17/11/2026) y Forbes Argentina (2025); música *"Inspired"* de
Kevin MacLeod (incompetech.com, CC BY 4.0); foto de obra de Flocci Nivis
(Wikimedia Commons, CC BY 4.0).

El video se genera con Python (Pillow) + ffmpeg, cuadro por cuadro. Pipeline,
guion y comandos de re-render en [video/README.md](video/README.md).

---

## 📁 Estructura del repositorio

```
backend/       API NestJS (módulos: auth, users, works, sync, certifications, notifications, audit-logs)
frontend/      App Flutter (features/{domain,data,presentation})
docs/          Documentación técnica + guía de despliegue
video/         Pipeline del video de presentación (scripts y guion; binarios fuera de git)
```

---

## 📅 Estado del proyecto

- **Sprints 1 a 7 completados** (MVP + mejoras post-MVP).
- Versión oficial etiquetada **`v1.0.0-mvp`** y desplegada.
- Suites: **408** tests de Flutter, **141** unitarios y **74** e2e de backend, todas en verde.

### Limitaciones conocidas

| Limitación | Alcance |
|---|---|
| Evidencias en web | El binario vive como `blob:` del navegador y muere al recargar (queda pendiente de sincronizar); los hitos y actas sí persisten |
| Notificaciones y auditoría | Se guardan en la base local del dispositivo; el envío al backend no está cableado |
| Adjuntos del backend | Disco efímero en Railway: se pierden en cada redeploy |
| CORS | Abierto (`*`); restringir al dominio propio antes de un uso real |
| Dominio propio | Pendiente: se agrega desde Vercel/Railway sin recompilar |

---

## 👤 Autor

**Nicolás Sebastián del Río**
Estudiante de Ingeniería en Informática — Universidad del Salvador (USAL)
[Sitio](https://constructing-three.vercel.app) · [GitHub](https://github.com/NicolasSebastiandelRio)

**Materia:** Seminario de Integración Profesional · **Docente:** Lic. C. López Pasaron · **Año:** 2026

---

## ⚖️ Licencia y propiedad intelectual

**ConstructING — Ecosistema de Gestión y Auditoría Técnica de Obras.**
Copyright (c) 2026 Nicolás Sebastián del Río. Todos los derechos reservados.

Proyecto de código cerrado y propiedad intelectual exclusiva de su autor.
Ninguna parte de este software, documentación (especificaciones de
requerimientos, diagramas UML, modelo entidad-relación y prototipos) ni archivos
asociados puede ser reproducida, distribuida o transmitida por ningún medio sin
la autorización expresa y por escrito del autor.
