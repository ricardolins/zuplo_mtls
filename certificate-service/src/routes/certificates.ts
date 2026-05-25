import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { CertService } from '../services/cert.service';
import { CAService } from '../services/ca.service';
import { AppError } from '../middleware/errorHandler';

const router = Router();

const caService = new CAService(
  process.env.STEP_CA_URL ?? 'https://step-ca-svc:9000',
  process.env.STEP_CA_FINGERPRINT ?? '',
  process.env.PROVISIONER_NAME ?? 'cert-manager',
  process.env.PROVISIONER_PASSPHRASE ?? ''
);
const certService = new CertService(caService);

const IssueSchema = z.object({
  commonName: z.string().min(3).max(64),
  organization: z.string().min(2).max(64),
  organizationalUnit: z.string().max(64).optional(),
  country: z.string().length(2).optional(),
  san: z.array(z.string()).max(5).optional(),
  ttl: z.string().regex(/^\d+(h|d)$/).optional(),
});

const RevokeSchema = z.object({
  reason: z.enum([
    'unspecified', 'keyCompromise', 'caCompromise',
    'affiliationChanged', 'superseded', 'cessationOfOperation',
  ]).default('unspecified'),
});

function getTenantId(req: Request): string {
  const id = req.headers['x-tenant-id'] as string;
  if (!id) throw new AppError(401, 'Missing X-Tenant-Id header', 'MISSING_TENANT');
  return id;
}

router.post('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const body = IssueSchema.parse(req.body);
    const cert = await certService.issue(getTenantId(req), body);
    res.status(201).json({
      id: cert.id,
      serialNumber: cert.serialNumber,
      commonName: cert.commonName,
      certPem: cert.certPem,
      chainPem: cert.chainPem,
      privateKeyPem: cert.privateKeyPem,
      issuedAt: cert.issuedAt,
      expiresAt: cert.expiresAt,
      status: cert.status,
    });
  } catch (err) { next(err); }
});

router.get('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const certs = await certService.list(getTenantId(req));
    res.json({ data: certs, total: certs.length });
  } catch (err) { next(err); }
});

router.get('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const cert = await certService.get(req.params.id, getTenantId(req));
    if (!cert) throw new AppError(404, 'Certificate not found', 'NOT_FOUND');
    const { privateKeyPem: _k, ...safe } = cert;
    res.json(safe);
  } catch (err) { next(err); }
});

router.delete('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { reason } = RevokeSchema.parse(req.body);
    await certService.revoke(req.params.id, getTenantId(req), reason);
    res.status(204).send();
  } catch (err) { next(err); }
});

router.post('/:id/renew', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const cert = await certService.renew(req.params.id, getTenantId(req));
    res.status(201).json(cert);
  } catch (err) { next(err); }
});

export { router as certificatesRouter };
