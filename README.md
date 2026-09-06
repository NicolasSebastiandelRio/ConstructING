# ConstructING - Registrando Imperios 🏛️

<img width="400" height="400" alt="constructING" src="https://github.com/user-attachments/assets/5f4d8de2-b999-4ab1-b930-c0e63154d2d7" />


> **Ecosistema Mobile de Gestión y Auditoría Técnica de Obras.**  
> Reduciendo la asimetría de información entre el profesional y el propietario mediante evidencia fehaciente y transparencia técnica.

> ## 🎯 Estrategia de Producto
> **Desarrollo mobile-first, entrega como URL web.** La interfaz se diseña con
> mentalidad móvil primero, pero el producto final **NO es una app para
> descargar** (sin APK/AAB ni tiendas). El artefacto distribuible se genera con
> `flutter build web` y se sirve como una URL (ver
> `frontend/lib/core/config/deployment.dart`).

---

## 📌 Visión General
**ConstructING** es una solución diseñada para resolver la desconfianza y la falta de comunicación en desarrollos inmobiliarios y reformas. A diferencia de los métodos informales (WhatsApp, minutas en papel), ConstructING ofrece un registro inalterable del ciclo de vida de la obra.

### El Problema 🚩
Actualmente, el seguimiento de obra depende de la presencialidad constante del propietario o de informes técnicos difíciles de interpretar, lo que genera incertidumbre y potenciales conflictos legales.

### La Solución ✅
Una plataforma **Offline-First** que permite certificar hitos mediante evidencia multimedia georreferenciada y firmas digitales de conformidad en pantalla.

---

## ✨ Funcionalidades Clave (MVP)
*   **Certificación con Firma Digital**: Cierre de etapas críticas con rúbrica biométrica en el dispositivo.
*   **Evidencia Multimedia Georreferenciada**: Captura de fotos/videos vinculados automáticamente a coordenadas GPS para garantizar la veracidad del peritaje.
*   **Cálculo de Ruta Crítica (CPM)**: Ajuste automático de fechas de entrega ante desviaciones en hitos clave.
*   **Sincronización Offline-First**: Operatividad total en entornos de obra con baja conectividad; sincronización inteligente al detectar red.
*   **Audit Log Inalterable**: Trazabilidad completa de quién, cuándo y dónde se realizó cada modificación técnica.

---

## 🛠️ Stack Tecnológico Proyectado
Para garantizar robustez y escalabilidad, el ecosistema se basa en:

| Capa | Tecnología |
| :--- | :--- |
| **Frontend** | Flutter mobile-first → **entrega Web (URL)** |
| **Backend API** | NestJS (Node.js) |
| **Base de Datos** | PostgreSQL (PostGIS para georreferencia) |
| **Infraestructura** | Supabase / AWS |
| **Documentación** | UML, SRS bajo estándar IEEE |

---

## ▶️ Puesta en Marcha Local

### Opción A — Supabase (recomendada, sin instalar nada)
1. Crear el proyecto en [supabase.com](https://supabase.com) y anotar la password.
2. Completar `backend/.env` con los datos del proyecto (ver tabla de variables).
3. Arrancar el backend (crea el esquema automáticamente con `synchronize:true`):
```bash
cd backend
npm install
npm run start:dev   # API en http://localhost:3000
```

### Opción B — PostgreSQL local con Docker
Requisito: [Docker Desktop](https://www.docker.com/products/docker-desktop/) instalado y en ejecución.
```bash
docker compose up -d   # PostgreSQL 16 en puerto 5432, BD constructingsal
cd backend
npm install
npm run start:dev
```

### Variables de entorno (`backend/.env`)
| Variable | Ejemplo local (Docker) | Ejemplo Supabase | Descripción |
| :--- | :--- | :--- | :--- |
| `DB_HOST` | `localhost` | `db.xxxxx.supabase.co` | Host de PostgreSQL |
| `DB_PORT` | `5432` | `5432` | Puerto |
| `DB_USER` | `postgres` | `postgres` | Usuario |
| `DB_PASSWORD` | `postgres` | *(password del proyecto)* | Contraseña |
| `DB_NAME` | `constructingsal` | `postgres` | Base de datos |
| `DB_SSL` | *(omitir)* | `true` | Obligatorio en Postgres administrados (Supabase/Neon/RDS) |
| `MAIL_HOST` | `smtp.ethereal.email` | `smtp.ethereal.email` | Servidor SMTP |
| `MAIL_PORT` | `587` | `587` | Puerto SMTP |
| `MAIL_USER` | *(cuenta Ethereal)* | *(cuenta Ethereal)* | Usuario SMTP (crear en [ethereal.email](https://ethereal.email)) |
| `MAIL_PASS` | *(clave Ethereal)* | *(clave Ethereal)* | Contraseña SMTP |

> Los correos de Ethereal no llegan a casillas reales: se visualizan en
> [ethereal.email/login](https://ethereal.email/login) con el usuario y clave
> de la cuenta. Ideal para probar bienvenida (CU-12), recuperación (CU-03) e
> invitaciones (CU-22) sin spamear.

### Entrega Web (el producto final es una URL)
El mismo código mobile-first compila a web sin cambios (`flutter build web`
verificado). No se publica en tiendas:
```bash
cd frontend
flutter run -d chrome    # desarrollo en el navegador
flutter build web        # artefacto en build/web → subir a hosting estático
```
> Nota: en web, `flutter_secure_storage` persiste en `localStorage` (no es
> almacenamiento seguro real). Para producción web se recomienda migrar la
> sesión a cookies `httpOnly` gestionadas por el backend.

---

> Si ves `ECONNREFUSED 127.0.0.1:5432` al iniciar el backend, no hay ningún
> PostgreSQL alcanzable con esos valores: verificá el contenedor
> (`docker compose ps`) o los datos del proyecto en Supabase.

---

## 📅 Hoja de Ruta (Seminario de Integración Profesional)

### Fase 1: Planeamiento y Arquitectura (Q1 2026) 🏗️
*   [x] Project Charter y Definición de Objetivos SMART.
*   [x] Especificación de Requerimientos de Software (SRS).
*   [x] Diseño de Modelo Entidad-Relación (DER).
*   [x] Especificación de Casos de Uso y Diagramas UML.
*   [x] Prototipado de Alta Fidelidad en Figma.
*   [x] Armado de tablero gantt

### Fase 2: Desarrollo y Entrega (Q2 2026) 🚀
*   [ ] Configuración de entorno Backend y Base de Datos.
*   [ ] Implementación de Módulos Core (Evidencia y Firmas).
*   [ ] Pruebas de Integración y Modo Offline.
*   [ ] Defensa Final (Diciembre 2026).

---

## 📁 Estructura del Repositorio
*   [`/docs`](/docs): Documentación técnica integral del proyecto.

---

## 👤 Autor
**Nicolas Sebastian del Rio**  
Estudiante de Ingeniería en Informática - Universidad del Salvador (USAL).  
[GitHub](https://github.com/nicolassebastiandelrio) | [Portfolio]([https://nicolassebastiandelrio.github.io/webPortfolio/](https://nicolassebastiandelrio.github.io/portfolioWeb-ndelrio/))

---

## ⚖️ Licencia y Propiedad Intelectual
**ConstructING - Ecosistema de Gestión y Auditoría Técnica de Obras.**
Copyright (c) 2026 Nicolas Sebastian del Rio. All rights reserved.

Este proyecto es de código cerrado y propiedad intelectual exclusiva de su autor. Ninguna parte de este software, documentación (incluyendo especificaciones de requerimientos, diagramas UML, Modelo Entidad-Relación y prototipos) o archivos asociados puede ser reproducida, distribuida o transmitida en forma alguna o por ningún medio, sin la autorización expresa y por escrito del autor.
