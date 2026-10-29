import { IsEmail, IsNotEmpty, MaxLength } from 'class-validator';

/** CU-22 paso 1: solicitud de invitación para un correo no registrado. */
export class CreateInvitationDto {
  @IsEmail({}, { message: 'El correo del invitado debe tener un formato válido.' })
  @MaxLength(150, { message: 'El correo del invitado no puede superar los 150 caracteres.' })
  @IsNotEmpty({ message: 'El correo del invitado es obligatorio.' })
  email!: string;
}