import { PartialType } from '@nestjs/mapped-types';
import { CreateWorkDto } from './create-work.dto';
import { IsOptional, IsEnum } from 'class-validator';
import { WorkStatus } from '../entities/work.entity';

export class UpdateWorkDto extends PartialType(CreateWorkDto) {
  @IsOptional()
  @IsEnum(WorkStatus, { message: 'Estado de obra inválido.' })
  estado?: WorkStatus;
}