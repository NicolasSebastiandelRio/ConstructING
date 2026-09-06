import { PartialType } from '@nestjs/mapped-types';
import { CreateWorkDto } from './create-work.dto';

/**
 * CU-17: edición de datos administrativos de la obra.
 * Hereda todos los campos de creación como opcionales (PartialType), incluido
 * el re-vínculo de propietario de CU-14. El `estado` NO forma parte de la
 * edición general: los cambios de fase pertenecen a CU-20
 * (PATCH /works/:id/status, con registro de auditoría CU-60).
 */
export class UpdateWorkDto extends PartialType(CreateWorkDto) {}