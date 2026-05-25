import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { v4 as uuidv4 } from 'uuid';

const router = Router();

const CreateTenantSchema = z.object({
  name: z.string().min(2).max(128),
  legalName: z.string().min(2).max(256),
  cnpj: z.string().length(14).optional(),
  contactEmail: z.string().email(),
});

const tenants = new Map<string, object>();

router.post('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const body = CreateTenantSchema.parse(req.body);
    const tenant = { id: uuidv4(), ...body, createdAt: new Date(), status: 'active' };
    tenants.set(tenant.id, tenant);
    res.status(201).json(tenant);
  } catch (err) {
    next(err);
  }
});

router.get('/:id', (req: Request, res: Response) => {
  const tenant = tenants.get(req.params.id);
  if (!tenant) { res.status(404).json({ error: 'NOT_FOUND' }); return; }
  res.json(tenant);
});

export { router as tenantsRouter };
