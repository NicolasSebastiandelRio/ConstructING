import { PartialType } from '@nestjs/mapped-types';
import { IsString, IsEmail, IsOptional, MinLength } from 'class-validator';

export class UpdateUserDto {
  @IsOptional()
  @IsString({ message: 'El nombre debe ser un texto válido.' })
  nombre?: string;

  @IsOptional()
  @IsEmail({}, { message: 'El formato del correo electrónico es inválido.' })
  email?: string;

  @IsOptional()
  @IsString()
  @MinLength(8, { message: 'La contraseña debe tener al menos 8 caracteres.' })
  password?: string;
}