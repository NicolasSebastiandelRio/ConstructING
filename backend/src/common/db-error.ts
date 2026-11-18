import { QueryFailedError } from 'typeorm';

/**
 * Detecta una violación de restricción UNIQUE del motor de base de datos.
 * Códigos: '23505' (PostgreSQL) y 'SQLITE_CONSTRAINT_UNIQUE' (better-sqlite3,
 * usado en el entorno de pruebas/E2E). Respaldo de CU-10 que convierte el
 * error de motor en un error de dominio con mensaje de la especificación.
 */
export function isUniqueConstraintViolation(error: unknown): boolean {
  if (!(error instanceof QueryFailedError)) return false;
  const code = (error as { code?: string }).code;
  return code === '23505' || code === 'SQLITE_CONSTRAINT_UNIQUE';
}