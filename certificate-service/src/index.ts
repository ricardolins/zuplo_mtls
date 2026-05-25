import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import { collectDefaultMetrics, Registry } from 'prom-client';
import { logger } from './middleware/logger';
import { certificatesRouter } from './routes/certificates';
import { tenantsRouter } from './routes/tenants';
import { healthRouter } from './routes/health';
import { metricsRouter } from './routes/metrics';
import { errorHandler } from './middleware/errorHandler';
import { requestLogger } from './middleware/requestLogger';

const app = express();
const metricsApp = express();
const register = new Registry();

collectDefaultMetrics({ register });

app.use(helmet());
app.use(cors({ origin: false }));
app.use(express.json({ limit: '100kb' }));
app.use(requestLogger);

app.use('/v1/health', healthRouter);
app.use('/v1/certificates', certificatesRouter);
app.use('/v1/tenants', tenantsRouter);

app.use(errorHandler);

metricsApp.use('/metrics', metricsRouter(register));

const PORT = parseInt(process.env.PORT ?? '3000', 10);
const METRICS_PORT = 3001;

app.listen(PORT, () => {
  logger.info({ msg: 'Certificate Service started', port: PORT });
});

metricsApp.listen(METRICS_PORT, () => {
  logger.info({ msg: 'Metrics endpoint started', port: METRICS_PORT });
});

export { app };
