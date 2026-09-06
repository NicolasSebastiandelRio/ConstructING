import { BadRequestException, GoneException, NotFoundException } from '@nestjs/common';
import { WorkInvitationEntity } from './entities/work-invitation.entity';

/** Vigencia temporal del código de invitación (CU-22: "código único temporal"). */
export const INVITATION_EXPIRY_DAYS = 7;

/** Alfabeto sin caracteres ambiguos (0/O, 1/I/L) para códigos legibles. */
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_PREFIX = 'CNG-';
const CODE_RANDOM_LENGTH = 6;

/** Genera un código único legible, ej. CNG-7K2P9Q (paso 2 del CU-22). */
export function generateInvitationCode(): string {
  let suffix = '';
  for (let i = 0; i < CODE_RANDOM_LENGTH; i++) {
    suffix += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return `${CODE_PREFIX}${suffix}`;
}

/** Normaliza correos para comparar invitación vs registro sin falsos negativos. */
export function normalizeInvitationEmail(email: string): string {
  return email.trim().toLowerCase();
}

/**
 * Predicado puro compartido por el reclamo en el registro (CU-06/CU-22) y la
 * consulta del código: la invitación debe existir, estar pendiente y vigente,
 * y el correo debe coincidir con el invitado.
 */
export function assertInvitationClaimable(
  invitation: WorkInvitationEntity | null,
  email: string,
  now: Date = new Date(),
): asserts invitation is WorkInvitationEntity {
  if (!invitation) {
    throw new NotFoundException('El código de invitación no existe.');
  }
  if (invitation.usedAt) {
    throw new GoneException('El código de invitación ya fue utilizado.');
  }
  if (invitation.expiresAt.getTime() <= now.getTime()) {
    throw new GoneException('El código de invitación expiró.');
  }
  if (normalizeInvitationEmail(invitation.email) !== normalizeInvitationEmail(email)) {
    throw new BadRequestException('El código de invitación no corresponde a este correo.');
  }
}
