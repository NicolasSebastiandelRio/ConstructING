import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { UserEntity } from '../auth/user.entity';
import { UpdateUserDto } from './dto/update-user.dto';


@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
  ) {}

  /**
   * CU-09: Consultar listado general de usuarios (Activos e inactivos para Administrador)
   */
  async findAll(): Promise<UserEntity[]> {
    return await this.userRepository.find({
      withDeleted: true, // Incluye cuentas inhabilitadas para la gestión de auditoría
    });
  }

  /**
   * Visualizar perfil de usuario específico por ID
   */
  async findOne(id: string): Promise<UserEntity> {
    const user = await this.userRepository.findOne({ 
      where: { id }, 
      withDeleted: true 
    });
    
    if (!user) {
      throw new NotFoundException(`El usuario con ID ${id} no fue encontrado.`);
    }
    
    return user;
  }

  /**
   * CU-07: Modificar datos de usuario
   */
  async update(id: string, updateUserDto: UpdateUserDto): Promise<UserEntity> {
    const user = await this.findOne(id);

    // Validar unicidad de correo si se intenta modificar (CU-10 / CU-07 Flujo Alterno)
    if (updateUserDto.email && updateUserDto.email !== user.email) {
      const existingEmail = await this.userRepository.findOne({ 
        where: { email: updateUserDto.email } 
      });
      if (existingEmail) {
        throw new BadRequestException('El correo electrónico ya se encuentra registrado por otro usuario.');
      }
    }

    Object.assign(user, updateUserDto);
    return await this.userRepository.save(user);
  }

  /**
   * CU-08: Dar de baja / Inhabilitar usuario (Soft-Delete - RNF-S-03)
   */
  async softDelete(id: string): Promise<void> {
    await this.findOne(id);
    await this.userRepository.softDelete(id);
  }
}