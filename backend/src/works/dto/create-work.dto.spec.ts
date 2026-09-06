import { validate } from 'class-validator';
import { CreateWorkDto } from './create-work.dto';

describe('CreateWorkDto - CU-15 (Establecer Ubicación Geográfica)', () => {
  const base = {
    nombre: 'Edificio Central',
    direccion: 'Av. Libertador 1234',
    fechaInicio: '2026-09-01',
    propietarioEmail: 'dueño@gmail.com',
  };

  it('acepta coordenadas válidas dentro de los rangos geográficos', async () => {
    const dto = Object.assign(new CreateWorkDto(), {
      ...base,
      latitud: -34.6037,
      longitud: -58.3816,
    });

    expect(await validate(dto)).toHaveLength(0);
  });

  it('acepta la obra sin coordenadas (el ancla puede fijarse en la edición)', async () => {
    const dto = Object.assign(new CreateWorkDto(), base);

    expect(await validate(dto)).toHaveLength(0);
  });

  it('rechaza latitudes fuera del rango -90..90', async () => {
    const dto = Object.assign(new CreateWorkDto(), { ...base, latitud: 91 });

    const errors = await validate(dto);
    expect(errors).toHaveLength(1);
    expect(errors[0].property).toBe('latitud');
    expect(Object.values(errors[0].constraints ?? {}).join(' ')).toContain('-90 y 90');
  });

  it('rechaza longitudes fuera del rango -180..180', async () => {
    const dto = Object.assign(new CreateWorkDto(), { ...base, longitud: 200 });

    const errors = await validate(dto);
    expect(errors).toHaveLength(1);
    expect(errors[0].property).toBe('longitud');
    expect(Object.values(errors[0].constraints ?? {}).join(' ')).toContain('-180 y 180');
  });

  it('rechaza coordenadas no numéricas', async () => {
    const dto = Object.assign(new CreateWorkDto(), { ...base, latitud: 'norte' });

    const errors = await validate(dto);
    expect(errors.some((e) => e.property === 'latitud')).toBe(true);
  });
});