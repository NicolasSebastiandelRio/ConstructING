import { IsString, IsNotEmpty, IsDateString, IsUUID, IsOptional, MaxLength, IsNumber } from 'class-validator';

export class CreateWorkDto {
  @IsString()
  @IsNotEmpty({ message: 'El nombre de la obra es obligatorio.' })
  nombre!: string;

  @IsString()
  @IsNotEmpty({ message: 'La dirección es obligatoria.' })
  direccion!: string;

  @IsDateString({}, { message: 'La fecha de inicio debe tener un formato válido (YYYY-MM-DD).' })
  fechaInicio!: string;

  @IsOptional()
  @IsString({ message: 'La descripción debe ser un texto válido.' })
  @MaxLength(500, { message: 'La descripción no puede superar los 500 caracteres.' })
  descripcion?: string;

  @IsUUID('4', { message: 'El ID del propietario debe ser un UUID válido.' })
  propietarioId!: string;

  @IsOptional()
  @IsNumber()
  latitud?: number;

  @IsOptional()
  @IsNumber()
  longitud?: number;
}