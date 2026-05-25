import { Router, Request, Response } from 'express';
import { Registry } from 'prom-client';

export function metricsRouter(register: Registry): Router {
  const router = Router();
  router.get('/', async (_req: Request, res: Response) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  });
  return router;
}
