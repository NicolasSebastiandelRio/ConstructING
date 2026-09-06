import { QueryFailedError } from 'typeorm';
import { isUniqueConstraintViolation } from './db-error';

describe('isUniqueConstraintViolation - CU-10 (respaldo de BD)', () => {
  it('reconoce el código PostgreSQL 23505', () => {
    const err = new QueryFailedError('SELECT', [] as never, { code: '23505' } as never);
    expect(isUniqueConstraintViolation(err)).toBe(true);
  });

  it('reconoce el código SQLite SQLITE_CONSTRAINT_UNIQUE (entorno de test/E2E)', () => {
    const err = new QueryFailedError('SELECT', [] as never, { code: 'SQLITE_CONSTRAINT_UNIQUE' } as never);
    expect(isUniqueConstraintViolation(err)).toBe(true);
  });

  it('ignora errores que no son de unicidad', () => {
    const err = new QueryFailedError('SELECT', [] as never, { code: '23503' } as never);
    expect(isUniqueConstraintViolation(err)).toBe(false);
  });

  it('retorna false para errores que no son QueryFailedError', () => {
    expect(isUniqueConstraintViolation(new Error('generic'))).toBe(false);
    expect(isUniqueConstraintViolation(null)).toBe(false);
    expect(isUniqueConstraintViolation('23505')).toBe(false);
  });
});