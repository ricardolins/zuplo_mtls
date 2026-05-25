import { v4 as uuidv4 } from 'uuid';
import { CAService, CertificateRequest, RevocationReason } from './ca.service';
import { logger } from '../middleware/logger';
import { Counter, Histogram } from 'prom-client';

const issuedCounter = new Counter({
  name: 'mtls_certificates_issued_total',
  help: 'Total certificates issued',
  labelNames: ['tenant_id'],
});

const revokedCounter = new Counter({
  name: 'mtls_certificates_revoked_total',
  help: 'Total certificates revoked',
  labelNames: ['tenant_id', 'reason'],
});

const signDuration = new Histogram({
  name: 'step_ca_sign_duration_seconds',
  help: 'Duration of certificate signing operations',
  buckets: [0.1, 0.25, 0.5, 1, 2.5, 5],
});

export interface IssuedCertificate {
  id: string;
  tenantId: string;
  serialNumber: string;
  commonName: string;
  certPem: string;
  chainPem: string;
  privateKeyPem: string;
  issuedAt: Date;
  expiresAt: Date;
  status: 'active' | 'revoked' | 'expired';
}

export class CertService {
  private readonly store = new Map<string, IssuedCertificate>();

  constructor(private readonly caService: CAService) {}

  async issue(tenantId: string, request: CertificateRequest): Promise<IssuedCertificate> {
    const timer = signDuration.startTimer();
    try {
      const signed = await this.caService.sign(request);

      const cert: IssuedCertificate = {
        id: uuidv4(),
        tenantId,
        serialNumber: signed.serialNumber,
        commonName: request.commonName,
        certPem: signed.certPem,
        chainPem: signed.chainPem,
        privateKeyPem: signed.privateKeyPem,
        issuedAt: new Date(),
        expiresAt: signed.expiresAt,
        status: 'active',
      };

      this.store.set(cert.id, cert);
      issuedCounter.inc({ tenant_id: tenantId });
      logger.info({ msg: 'Certificate issued', certId: cert.id, tenantId, cn: request.commonName });
      return cert;
    } finally {
      timer();
    }
  }

  async get(id: string, tenantId: string): Promise<IssuedCertificate | null> {
    const cert = this.store.get(id);
    if (!cert || cert.tenantId !== tenantId) return null;
    return cert;
  }

  async list(tenantId: string): Promise<Omit<IssuedCertificate, 'privateKeyPem'>[]> {
    return Array.from(this.store.values())
      .filter(c => c.tenantId === tenantId)
      .map(({ privateKeyPem: _key, ...rest }) => rest);
  }

  async revoke(id: string, tenantId: string, reason: RevocationReason): Promise<void> {
    const cert = await this.get(id, tenantId);
    if (!cert) throw new Error('Certificate not found');
    if (cert.status === 'revoked') throw new Error('Certificate already revoked');

    await this.caService.revoke(cert.serialNumber, reason);
    cert.status = 'revoked';
    revokedCounter.inc({ tenant_id: tenantId, reason });
    logger.info({ msg: 'Certificate revoked', certId: id, tenantId, reason });
  }

  async renew(id: string, tenantId: string): Promise<IssuedCertificate> {
    const existing = await this.get(id, tenantId);
    if (!existing) throw new Error('Certificate not found');
    if (existing.status === 'revoked') throw new Error('Cannot renew revoked certificate');

    const renewed = await this.issue(tenantId, { commonName: existing.commonName, organization: '' });
    await this.revoke(id, tenantId, 'superseded');
    return renewed;
  }
}
