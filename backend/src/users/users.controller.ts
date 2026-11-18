import { Controller, Get, Body, Param, Patch, Post, Delete, HttpCode, HttpStatus } from '@nestjs/common';
import { UsersService } from './users.service';
import { UpdateUserDto } from './dto/update-user.dto';
import { UserEntity } from '../auth/user.entity';


@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get()
  findAll() {
    return this.usersService.findAll().then((users) => users.map(this.sanitize));
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.usersService.findOne(id).then(this.sanitize);
  }

  @Patch(':id')
  update(@Param('id') id: string, @Body() updateUserDto: UpdateUserDto) {
    return this.usersService.update(id, updateUserDto).then(this.sanitize);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('id') id: string) {
    return this.usersService.softDelete(id);
  }

  /**
   * CU-08 (complemento operativo): POST /users/:id/restore habilita un
   * usuario inhabilitado (limpia la marca de borrado lógico).
   */
  @Post(':id/restore')
  @HttpCode(HttpStatus.OK)
  restore(@Param('id') id: string) {
    return this.usersService.restore(id).then((user) => this.sanitize(user));
  }

  /** Elimina el hash de contraseña antes de enviar datos a la UI (seguridad). */
  private sanitize<T extends UserEntity>(user: T): Omit<T, 'passwordHash'> {
    const { passwordHash, ...rest } = user;
    void passwordHash;
    return rest;
  }
}