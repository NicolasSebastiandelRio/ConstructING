import { validate } from 'class-validator';
import { UpdateWorkDto } from './update-work.dto';

describe('UpdateWorkDto - CU-30 (fecha_fin_estimada)', () => {
  it('acepta una fecha estimada válida', async () => {
    const dto = Object.assign(new UpdateWorkDto(), {
      fechaFinEstimada: '2026-10-15',
    });

    expect(await validate(dto)).toHaveLength(0);
  });

  it('acepta el DTO sin fecha estimada (edición clásica CU-17)', async () => {
    const dto = Object.assign(new UpdateWorkDto(), { nombre: 'Obra X' });

    expect(await validate(dto)).toHaveLength(0);
  });

  it('rechaza una fecha estimada con formato inválido', async () => {
    const dto = Object.assign(new UpdateWorkDto(), {
      fechaFinEstimada: '15-10-2026',
    });

    const errors = await validate(dto);
    expect(errors).toHaveLength(1);
    expect(errors[0].property).toBe('fechaFinEstimada');
  });
});
