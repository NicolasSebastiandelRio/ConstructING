import { BadRequestException } from '@nestjs/common';

/**
 * Política de complejidad de contraseña (RNF_S_01 / CU-06 Flujo Alt. 3.2).
 * Exige al menos 8 caracteres y un número. Compartida por los flujos de
 * registro (CU-06), recuperación (CU-03) y actualización de perfil (CU-07).
 */
export function validatePasswordPolicy(password: string): void {
  const hasMinimumLength = password.length >= 8;
  const hasNumber = /\d/.test(password);
  if (!hasMinimumLength || !hasNumber) {
    throw new BadRequestException('La contraseña debe tener al menos 8 caracteres y un número');
  }
}