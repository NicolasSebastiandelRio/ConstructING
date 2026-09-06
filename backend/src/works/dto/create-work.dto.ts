import { IsString, IsNotEmpty, IsDateString, IsUUID, IsOptional, IsEmail, IsNumber, Min, Max, MaxLength } from 'class-validator';

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

  @IsOptional()
  @IsUUID('4', { message: 'El ID del propietario debe ser un UUID válido.' })
  propietarioId?: string;

  /**
   * CU-13 paso 1 + CU-14: vinculación del propietario por correo electrónico.
   * Al menos uno entre `propietarioId` y `propietarioEmail` debe informarse
   * (el servicio rechaza la creación si no se puede resolver el propietario).
   */
  @IsOptional()
  @IsEmail({}, { message: 'El correo del propietario debe tener un formato válido.' })
  @MaxLength(150, { message: 'El correo del propietario no puede superar los 150 caracteres.' })
  propietarioEmail?: string;

  /**
   * CU-15 paso 4: ancla geográfica de la obra. Las coordenadas deben ser
   * geográficamente válidas (los valores fuera de rango se rechazan con 400
   * gracias al ValidationPipe global).
   */
  @IsOptional()
  @IsNumber({}, { message: 'La latitud debe ser un número válido.' })
  @Min(-90, { message: 'La latitud debe estar entre -90 y 90 grados.' })
  @Max(90, { message: 'La latitud debe estar entre -90 y 90 grados.' })
  latitud?: number;

  @IsOptional()
  @IsNumber({}, { message: 'La longitud debe ser un número válido.' })
  @Min(-180, { message: 'La longitud debe estar entre -180 y 180 grados.' })
  @Max(180, { message: 'La longitud debe estar entre -180 y 180 grados.' })
  longitud?: number;
}