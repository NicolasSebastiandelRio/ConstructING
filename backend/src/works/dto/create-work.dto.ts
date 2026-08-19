import { IsString, IsNotEmpty, IsDateString, IsUUID, IsOptional, IsNumber } from 'class-validator';

export class CreateWorkDto {
  @IsString()
  @IsNotEmpty({ message: 'El nombre de la obra es obligatorio.' })
  nombre!: string;

  @IsString()
  @IsNotEmpty({ message: 'La dirección es obligatoria.' })
  direccion!: string;

  @IsDateString({}, { message: 'La fecha de inicio debe tener un formato válido (YYYY-MM-DD).' })
  fechaInicio!: string;

  @IsUUID('4', { message: 'El ID del propietario debe ser un UUID válido.' })
  propietarioId!: string;

  @IsOptional()
  @IsNumber()
  latitud?: number;

  @IsOptional()
  @IsNumber()
  longitud?: number;
}