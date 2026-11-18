# Despliegue de la versión oficial (MVP)

Documento operativo para publicar **ConstructING** en un dominio propio.

- Versión oficial: `main` @ `v1.0.0-mvp` (merge del Sprint 7 / PT-09).
- Frontend: Flutter Web (build estático).
- Backend: NestJS (API REST).
- Base de datos: PostgreSQL en Supabase (ya operativa).

---

## 1. Arquitectura a publicar

```
https://app.TUDOMINIO.com      -> Flutter Web (estático)
https://api.TUDOMINIO.com      -> NestJS (API + archivos subidos)
https://<proyecto>.supabase.co -> PostgreSQL gestionado
```

El frontend se compila con la URL del backend incrustada:

```powershell
flutter build web --release --dart-define=API_BASE_URL=https://api.TUDOMINIO.com
```

> El valor por defecto es `http://localhost:3000`. Si se olvida el
> `--dart-define`, la app publicada intentará hablar con la PC del visitante y
> **no cargará datos**.

---

## 2. Requisitos previos

| Elemento | Detalle |
|---|---|
| Dominio | Registrado (Namecheap, Cloudflare, Porkbun, NIC.ar, etc.). |
| Frontend | Hosting estático: Netlify, Vercel, Cloudflare Pages o Firebase Hosting. |
| Backend | Host con Node 20+: Render, Railway, Fly.io o un VPS. |
| Base de datos | El proyecto Supabase actual (mismas credenciales del `.env`). |
| Correo | SMTP actual (`MAIL_*`), necesario para invitaciones y notificaciones por mail. |

### Variables de entorno del backend

| Variable | Uso |
|---|---|
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_SSL` | Conexión a Supabase (`DB_SSL=true`). |
| `MAIL_HOST`, `MAIL_PORT`, `MAIL_USER`, `MAIL_PASS` | Envío de correos. |
| `PORT` | Puerto de escucha (los hosts lo inyectan). |
| `UPLOAD_DIR`, `CERTIFICATION_UPLOAD_DIR` | Carpetas de archivos subidos (actas y evidencias). |
| `APP_DOWNLOAD_URL` | URL pública del APK (si se distribuye la app móvil). |
| `NOTIFICATIONS_CRON_DISABLED` | `true` solo si se desactiva el cron del servidor. |

> ⚠️ **Los archivos subidos viven en disco.** En hosts con sistema de archivos
> efímero (Render/Railway sin volumen) los adjuntos se pierden en cada
> redeploy. Para la demo alcanza; para uso real hay que montar un disco
> persistente o mover los adjuntos a un bucket (S3/R2/Supabase Storage).

### CORS

`backend/src/main.ts` habilita `origin: '*'` (pensado para desarrollo). Antes
de publicar conviene restringirlo al dominio del frontend:

```ts
app.enableCors({
  origin: ['https://app.TUDOMINIO.com'],
  methods: 'GET,HEAD,PUT,PATCH,POST,DELETE',
});
```

---

## 3. Publicar el frontend

```powershell
cd frontend
flutter build web --release --dart-define=API_BASE_URL=https://api.TUDOMINIO.com
```

Se genera `frontend/build/web`. Ese directorio es el sitio completo: debe
publicarse **tal cual**, incluyendo:

- `index.html`, `flutter_bootstrap.js`, `main.dart.js`, `manifest.json`
- `assets/` (logo, tipografías)
- **`sqlite3.wasm` y `sqflite_sw.js`** — imprescindibles: son la base de datos
  local en el navegador (IndexedDB). Si faltan, la app abre sin datos.

Configuración típica en el host:

| Campo | Valor |
|---|---|
| Directorio de publicación | `frontend/build/web` |
| Comando de build | `flutter build web --release --dart-define=API_BASE_URL=https://api.TUDOMINIO.com` |
| Rewrite / fallback | Todas las rutas → `/index.html` |

Recomendación para Netlify/Vercel: instalar Flutter en el entorno de build o,
más simple, **compilar en local y subir `build/web`** (arrastrar la carpeta o
`netlify deploy --dir=build/web --prod`).

---

## 4. Publicar el backend

```powershell
cd backend
npm ci
npm run build
npm run start:prod      # requiere PORT y las variables del punto 2
```

- Healthcheck sugerido: `GET /` (el controlador raíz responde).
- Mantener `DB_SSL=true`.
- Verificar tras el primer arranque que TypeORM creó/validó el esquema sin
  errores y que `POST /auth/login` responde.

---

## 5. Dominio y DNS

| Tipo | Nombre | Valor |
|---|---|---|
| CNAME | `app` | host del frontend (ej. `tu-sitio.netlify.app`) |
| CNAME | `api` | host del backend (ej. `constructing-api.onrender.com`) |

Ambos hosts emiten el certificado TLS automáticamente al validar el CNAME.

También se puede publicar el frontend en la raíz (`TUDOMINIO.com`) apuntando
el dominio apex al host estático.

---

## 6. Verificación posterior al despliegue

1. **Login** de ambos roles (Profesional y Propietario).
2. **Datos reales**: que la lista de obras cargue (si está vacía, el
   `API_BASE_URL` quedó mal o CORS bloquea).
3. **Persistencia local**: recargar la página y confirmar que la Hoja de Ruta
   conserva los hitos (valida `sqlite3.wasm` + IndexedDB).
4. **Captura de evidencia**: subir una foto (JPG o PNG; el PNG se convierte) y
   comprobar que la marca de agua aparece abajo, sin tapar la imagen.
5. **Certificación**: firmar como profesional y como propietario, y descargar
   el acta PDF (logo + datos concisos).
6. **Campana**: el propietario debe ver “Avance en …” tras una evidencia y el
   profesional “El propietario firmó el acta” tras la firma.

---

## 7. Limitaciones conocidas de esta versión

- **Evidencias en web**: el binario se guarda como `blob:` del navegador; al
  recargar la página la URL muere y la evidencia queda pendiente de
  sincronizar. Los registros (hitos, actas) sí persisten.
- **Notificaciones y auditoría**: se guardan en la base local del dispositivo.
  El backend expone `POST /audit-logs` y el de notificaciones, pero el envío
  remoto todavía no está cableado desde la app.
- **Adjuntos en el backend**: disco local (ver advertencia del punto 2).
