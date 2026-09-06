import { Injectable, NotFoundException, BadRequestException, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, Not, IsNull } from 'typeorm';
import { WorkEntity, WorkStatus } from './entities/work.entity';
import { CreateWorkDto } from './dto/create-work.dto';
import { UpdateWorkDto } from './dto/update-work.dto';
import { UserEntity } from '../auth/user.entity';

@Injectable()
export class WorksService {
  private readonly logger = new Logger(WorksService.name);

  constructor(
    @InjectRepository(WorkEntity)
    private readonly workRepository: Repository<WorkEntity>,
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
  ) {}

  /**
   * CU-14: Vincular Propietario a Obra. Resuelve el perfil por correo
   * electrónico (flujo normal, pasos 1-2) o por ID, y devuelve la entidad
   * lista para crear la relación (FK) en el paso 3.
   * CU-14 Alt. 2.2 → CU-22: si el correo no existe, la invitación se genera
   * explícitamente con POST /works/:id/invitations (requiere obra existente,
   * por eso no se dispara automáticamente en la creación).
   */
  private async resolvePropietario(
    propietarioEmail?: string,
    propietarioId?: string,
  ): Promise<UserEntity> {
    let propietario: UserEntity | null = null;
    if (propietarioEmail) {
      propietario = await this.userRepository.findOne({ where: { email: propietarioEmail } });
    } else if (propietarioId) {
      propietario = await this.userRepository.findOne({ where: { id: propietarioId } });
    }

    if (!propietario) {
      throw new BadRequestException(
        `El propietario con identificador '${propietarioEmail ?? propietarioId ?? ''}' no existe en el sistema.`,
      );
    }
    return propietario;
  }

  /**
   * CU-13: Crear Nueva Obra (paso 4: CU-14 Vincular Propietario + CU-15
   * Ubicación; paso 5: persistencia con estado inicial "En Planificación").
   */
  async create(createWorkDto: CreateWorkDto): Promise<WorkEntity> {
    const { propietarioEmail, propietarioId, ...workData } = createWorkDto;

    // CU-14: resolución del propietario por correo (flujo normal) o por ID.
    const propietario = await this.resolvePropietario(propietarioEmail, propietarioId);

    // 1. Creamos la instancia tipada de la obra
    const nuevaObra = this.workRepository.create({
      ...workData,
      // CU-13 Poscondición: la obra nace en estado "En Planificación"
      // (además del default de la entidad, se fija explícitamente para que el
      // cliente nunca pueda forzar otro estado inicial).
      estado: WorkStatus.PLANIFICATION,
      // CU-14 paso 3: se fija la FK y el objeto de la relación para que
      // TypeORM persista y devuelva la vinculación de forma consistente.
      propietario,
      propietarioId: propietario.id,
    });

    // 2. Guardamos y manejamos la sobrecarga de TypeORM de forma segura
    const savedResult = await this.workRepository.save(nuevaObra);

    // Si TypeORM retorna un array por inferencia, devolvemos el primer elemento; caso contrario, el objeto
    return Array.isArray(savedResult) ? savedResult[0] : savedResult;
  }

  /**
   * CU-18: Consultar Obras Asignadas (+ CU-21 paso 4: Historial). Devuelve las
   * obras vinculadas al usuario: con `propietarioId` filtra "Mis Obras" del
   * propietario; sin él devuelve el listado general (rol Profesional). Con
   * `archivedOnly` trae sólo las archivadas (historial); si no, sólo activas.
   */
  async findAll(propietarioId?: string, archivedOnly = false): Promise<WorkEntity[]> {
    return await this.workRepository.find({
      where: {
        ...(propietarioId ? { propietarioId } : {}),
        ...(archivedOnly ? { deletedAt: Not(IsNull()) } : {}),
      },
      relations: { propietario: true },
      withDeleted: archivedOnly,
    });
  }

  // CORRECIÓN: Retorna un único objeto WorkEntity o lanza excepción (CU-19)
  // Incluye archivadas (withDeleted) para que la ficha técnica y el historial
  // (CU-21) puedan consultarlas; la edición las bloquea en update().
  async findOne(id: string): Promise<WorkEntity> {
    const obra = await this.workRepository.findOne({
      where: { id },
      relations: { propietario: true },
      withDeleted: true,
    });

    if (!obra) {
      throw new NotFoundException(`La obra con ID ${id} no fue encontrada.`);
    }

    return obra;
  }

  // CORRECIÓN: Retorna un único objeto WorkEntity actualizado (CU-17)
  async update(id: string, updateWorkDto: UpdateWorkDto): Promise<WorkEntity> {
    const obra = await this.findOne(id);

    // CU-17 Precondición: la obra no debe estar archivada. El borrado lógico
    // (CU-21) marca deletedAt y fija el estado; ambos bloquean la edición con
    // un mensaje claro en lugar del NotFound genérico.
    if (obra.deletedAt || obra.estado === WorkStatus.ARCHIVED) {
      throw new BadRequestException(
        'No se puede modificar una obra archivada. La obra permanece inalterable en el historial (CU-21).',
      );
    }

    const { propietarioEmail, propietarioId, ...workData } = updateWorkDto;

    // CU-14 invocado desde la edición de obra: si se informa un nuevo
    // propietario (correo o ID), se verifica su existencia y se re-vincula
    // la FK; el campo virtual `propietarioEmail` nunca se persiste.
    // Se actualiza también el objeto `propietario`, porque TypeORM deriva la
    // FK de la relación cargada al guardar y de lo contrario ignoraría el
    // nuevo propietarioId.
    if (propietarioEmail || propietarioId) {
      const propietario = await this.resolvePropietario(propietarioEmail, propietarioId);
      obra.propietario = propietario;
      obra.propietarioId = propietario.id;
    }

    Object.assign(obra, workData);
    return await this.workRepository.save(obra);
  }

  /**
   * CU-20: Actualizar Estado del Proyecto (pasos 1-2). Valida el valor contra
   * el enum (el pipe ya lo hace en HTTP; aquí se defiende la llamada directa),
   * bloquea obras archivadas y deriva el archivado a CU-21 con sus
   * precondiciones propias. El paso 4 (Audit Log CU-60) aún no existe como
   * módulo: hasta entonces el cambio queda en traza estructurada.
   */
  async updateStatus(id: string, estado: WorkStatus): Promise<WorkEntity> {
    if (!Object.values(WorkStatus).includes(estado)) {
      throw new BadRequestException('Estado de obra inválido.');
    }

    const obra = await this.findOne(id);

    if (obra.deletedAt || obra.estado === WorkStatus.ARCHIVED) {
      throw new BadRequestException(
        'No se puede cambiar el estado de una obra archivada. La obra permanece inalterable en el historial (CU-21).',
      );
    }

    if (estado === WorkStatus.ARCHIVED) {
      throw new BadRequestException(
        'El archivado de una obra se realiza con CU-21 (DELETE /works/:id), que exige obra completada y sin hitos en ejecución.',
      );
    }

    const anterior = obra.estado;
    obra.estado = estado;
    const guardada = await this.workRepository.save(obra);

    // CU-20 paso 4 (transitorio hasta CU-60): traza estructurada del cambio.
    this.logger.log(
      `Obra ${id}: estado '${anterior}' → '${estado}'. Pendiente de persistir en Audit Log (CU-60).`,
    );
    return guardada;
  }

  /**
   * CU-21: Archivar Obra. Precondición: obra completada. Fija el estado
   * Archivado y aplica borrado lógico (RNF-S-03): la obra sale del listado
   * activo, queda visible en el historial (findOne withDeleted) e inalterable
   * (update/updateStatus la rechazan). El Alt. 2.1/2.2 (hitos "En Ejecución")
   * se cableará en el Sprint 3, cuando exista el módulo de Hitos (CU-23..30).
   */
  async archive(id: string): Promise<void> {
    const obra = await this.findOne(id);

    if (obra.deletedAt || obra.estado === WorkStatus.ARCHIVED) {
      throw new BadRequestException('La obra ya se encuentra archivada en el historial.');
    }

    if (obra.estado !== WorkStatus.COMPLETED) {
      throw new BadRequestException(
        `Solo se puede archivar una obra en estado '${WorkStatus.COMPLETED}'. Estado actual: '${obra.estado}'.`,
      );
    }

    obra.estado = WorkStatus.ARCHIVED;
    await this.workRepository.save(obra);
    await this.workRepository.softDelete(id);

    this.logger.log(`Obra ${id} archivada (CU-21). Pasa al historial como inalterable.`);
  }
}