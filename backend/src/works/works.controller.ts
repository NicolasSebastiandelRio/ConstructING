import { Controller, Get, Post, Body, Param, Patch, Delete, Query, HttpCode, HttpStatus } from '@nestjs/common';
import { WorksService } from './works.service';
import { InvitationsService } from './invitations.service';
import { CreateWorkDto } from './dto/create-work.dto';
import { UpdateWorkDto } from './dto/update-work.dto';
import { UpdateWorkStatusDto } from './dto/update-work-status.dto';
import { CreateInvitationDto } from './dto/create-invitation.dto';
import { WorkEntity } from './entities/work.entity';

type SafeWork = Omit<WorkEntity, 'propietario'> & {
  propietario?: Record<string, unknown> | null;
};

@Controller('works')
export class WorksController {
  constructor(
    private readonly worksService: WorksService,
    private readonly invitationsService: InvitationsService,
  ) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@Body() createWorkDto: CreateWorkDto) {
    return this.worksService.create(createWorkDto).then((work) => this.sanitize(work));
  }

  /**
   * CU-22 pasos 1-2: genera el código de invitación para un correo no
   * registrado, asociado a la obra (el correo viaja con CU-12 4.2).
   */
  @Post(':id/invitations')
  @HttpCode(HttpStatus.CREATED)
  createInvitation(@Param('id') id: string, @Body() dto: CreateInvitationDto) {
    return this.invitationsService.create(id, dto.email);
  }

  /**
   * CU-18 (+ CU-21 paso 4: Historial):
   * GET /works (general, Profesional) | GET /works?propietarioId=UUID
   * ("Mis Obras") | GET /works?archived=true (historial de archivadas).
   */
  @Get()
  findAll(
    @Query('propietarioId') propietarioId?: string,
    @Query('archived') archived?: string,
  ) {
    return this.worksService
      .findAll(propietarioId, archived === 'true')
      .then((works) => works.map((work) => this.sanitize(work)));
  }

  /**
   * CU-22: resuelve un código de invitación antes del registro.
   * Se declara ANTES de GET :id para que Express no capture "invitations"
   * como un ID de obra.
   */
  @Get('invitations/:code')
  resolveInvitation(@Param('code') code: string) {
    return this.invitationsService.resolve(code);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.worksService.findOne(id).then((work) => this.sanitize(work));
  }

  @Patch(':id')
  update(@Param('id') id: string, @Body() updateWorkDto: UpdateWorkDto) {
    return this.worksService.update(id, updateWorkDto).then((work) => this.sanitize(work));
  }

  /**
   * CU-20: PATCH /works/:id/status con { estado }. El DTO valida el enum;
   * el archivado se rechaza en el servicio (pertenece a CU-21).
   */
  @Patch(':id/status')
  updateStatus(@Param('id') id: string, @Body() dto: UpdateWorkStatusDto) {
    return this.worksService.updateStatus(id, dto.estado).then((work) => this.sanitize(work));
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  archive(@Param('id') id: string) {
    return this.worksService.archive(id);
  }

  /**
   * CU-19 (seguridad): la relación `propietario` se serializa con la entidad
   * completa; se elimina el hash de contraseña antes de responder, igual que
   * en UsersController.
   */
  private sanitize(work: WorkEntity): SafeWork {
    const { propietario, ...rest } = work;
    if (!propietario) {
      return { ...rest, propietario: propietario as null };
    }
    const { passwordHash, ...safeOwner } = propietario as unknown as Record<string, unknown>;
    void passwordHash;
    return { ...rest, propietario: safeOwner };
  }
}