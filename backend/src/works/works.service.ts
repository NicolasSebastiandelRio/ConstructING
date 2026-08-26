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

  // CORRECIÓN: Retorna un único objeto WorkEntity (Creación)
  async create(createWorkDto: CreateWorkDto): Promise<WorkEntity> {
    const { propietarioEmail, propietarioId, ...workData } = createWorkDto as any;

    let propietario;
    if (propietarioEmail) {
      propietario = await this.userRepository.findOne({ where: { email: propietarioEmail } });
    } else if (propietarioId) {
      propietario = await this.userRepository.findOne({ where: { id: propietarioId } });
    }

    if (!propietario) {
      throw new BadRequestException(
        `El propietario con identificador '${propietarioEmail ?? propietarioId}' no existe en el sistema.`
      );
    }

    // 1. Creamos la instancia tipada de la obra
    const nuevaObra = this.workRepository.create({
      ...workData,
      propietarioId: propietario.id,
    });

    // 2. Guardamos y manejamos la sobrecarga de TypeORM de forma segura
    const savedResult = await this.workRepository.save(nuevaObra);

    // Si TypeORM retorna un array por inferencia, devolvemos el primer elemento; caso contrario, el objeto
    return Array.isArray(savedResult) ? savedResult[0] : savedResult;
  }

  // CORRECIÓN CLAVE: Retorna una LISTA de entidades WorkEntity[] (CU-18)
  async findAll(): Promise<WorkEntity[]> {
    return await this.workRepository.find({
      relations: { propietario: true },
      withDeleted: false,
    });
  }

  // CORRECIÓN: Retorna un único objeto WorkEntity o lanza excepción (CU-19)
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

  // CORRECIÓN: Retorna un único objeto WorkEntity actualizado (CU-17)
  async update(id: string, updateWorkDto: UpdateWorkDto): Promise<WorkEntity> {
    const obra = await this.findOne(id);
    Object.assign(obra, updateWorkDto);
    return await this.workRepository.save(obra);
  }

  // CORRECIÓN: Retorna un único objeto WorkEntity con estado modificado (CU-20)
  async updateStatus(id: string, estado: WorkStatus): Promise<WorkEntity> {
    const obra = await this.findOne(id);
    obra.estado = estado;
    return await this.workRepository.save(obra);
  }

  // Borrado lógico (CU-21 / RNF-S-03)
  async archive(id: string): Promise<void> {
    const obra = await this.findOne(id);
    obra.estado = WorkStatus.ARCHIVED;
    await this.workRepository.save(obra);
    await this.workRepository.softDelete(id);
  }
}