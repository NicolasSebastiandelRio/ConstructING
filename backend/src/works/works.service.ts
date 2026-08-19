import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { WorkEntity, WorkStatus } from './entities/work.entity';
import { CreateWorkDto } from './dto/create-work.dto';
import { UpdateWorkDto } from './dto/update-work.dto';
import { UserEntity } from '../auth/user.entity';

@Injectable()
export class WorksService {
  constructor(
    @InjectRepository(WorkEntity)
    private readonly workRepository: Repository<WorkEntity>,
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
  ) {}

  /**
   * CU-13 y CU-16: Crear Nueva Obra con validación de propietario (CU-14 / RNF-D-03)
   */
  async create(createWorkDto: CreateWorkDto): Promise<WorkEntity> {
    const { propietarioId, ...workData } = createWorkDto;

    // Verificar existencia del propietario (Integridad referencial RNF-D-03)
    const propietario = await this.userRepository.findOne({ where: { id: propietarioId } });
    if (!propietario) {
      throw new BadRequestException(`El propietario con ID ${propietarioId} no existe en el sistema.`);
    }

    const nuevaObra = this.workRepository.create({
      ...workData,
      propietarioId,
    });

    return await this.workRepository.save(nuevaObra);
  }

  /**
   * CU-18: Consultar Obras Asignadas
   */
  async findAll(): Promise<WorkEntity[]> {
    return await this.workRepository.find({
      relations: { propietario: true },
      withDeleted: false, // Excluye las archivadas (Soft-Delete RNF-S-03)
    });
  }

  /**
   * CU-19: Visualizar Ficha Técnica de Obra por ID
   */
  async findOne(id: string): Promise<WorkEntity> {
    const obra = await this.workRepository.findOne({
      where: { id },
      relations: { propietario: true },
    });

    if (!obra) {
      throw new NotFoundException(`La obra con ID ${id} no fue encontrada.`);
    }

    return obra;
  }

  /**
   * CU-17: Modificar Información de Obra
   */
  async update(id: string, updateWorkDto: UpdateWorkDto): Promise<WorkEntity> {
    const obra = await this.findOne(id);

    if (updateWorkDto.propietarioId) {
      const propietario = await this.userRepository.findOne({ where: { id: updateWorkDto.propietarioId } });
      if (!propietario) {
        throw new BadRequestException(`El propietario con ID ${updateWorkDto.propietarioId} no existe.`);
      }
    }

    Object.assign(obra, updateWorkDto);
    return await this.workRepository.save(obra);
  }

  /**
   * CU-20: Actualizar Estado del Proyecto
   */
  async updateStatus(id: string, estado: WorkStatus): Promise<WorkEntity> {
    const obra = await this.findOne(id);
    obra.estado = estado;
    return await this.workRepository.save(obra);
  }

  /**
   * CU-21: Archivar Obra (Soft-Delete / Control lógico RNF-S-03)
   */
  async archive(id: string): Promise<void> {
    const obra = await this.findOne(id);
    obra.estado = WorkStatus.ARCHIVED;
    await this.workRepository.save(obra);
    await this.workRepository.softDelete(id); 
  }
}