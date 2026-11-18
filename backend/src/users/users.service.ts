import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { UserEntity } from '../auth/user.entity';
import { UpdateUserDto } from './dto/update-user.dto';
import { validatePasswordPolicy } from '../common/password-policy';
import { isUniqueConstraintViolation } from '../common/db-error';

const SALT_ROUNDS = 10;

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

    // CU-07 Flujo Alterno 3.1/3.2: validar unicidad de correo inmutable (CU-10)
    if (updateUserDto.email && updateUserDto.email !== user.email) {
      const existingEmail = await this.userRepository.findOne({ 
        where: { email: updateUserDto.email } 
      });
      if (existingEmail) {
        throw new BadRequestException('Correo ya registrado');
      }
    }

    // CU-07 + CU-11: si se modifica la contraseña, validar la política y
    // encriptarla antes de persistir (nunca guardar texto plano).
    const { password, ...rest } = updateUserDto;
    if (password) {
      validatePasswordPolicy(password);
      user.passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
    }

    Object.assign(user, rest);

    // CU-10 respaldo: si dos PATCH concurrentes intentan el mismo correo, la
    // restricción UNIQUE de la BD impide el duplicado (Flujo Alterno 3.2).
    try {
      const updated = await this.userRepository.save(user);
      // Evita exponer el hash en la respuesta.
      delete (updated as Partial<UserEntity>).passwordHash;
      return updated;
    } catch (error) {
      if (isUniqueConstraintViolation(error)) {
        throw new BadRequestException('Correo ya registrado');
      }
      throw error;
    }
  }

  /**
   * CU-08: Dar de baja / Inhabilitar usuario (Soft-Delete - RNF-S-03)
   */
  async softDelete(id: string): Promise<void> {
    await this.findOne(id);
    await this.userRepository.softDelete(id);
  }

  /**
   * CU-08 (complemento operativo): Habilitar un usuario inhabilitado.
   * TypeORM `restore` limpia la marca de borrado lógico dejando intacto
   * el resto del perfil.
   */
  async restore(id: string): Promise<UserEntity> {
    const user = await this.findOne(id); // withDeleted: incluye inactivos
    await this.userRepository.restore(id);
    user.deletedAt = null;
    return user;
  }
}