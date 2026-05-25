import axios, { AxiosInstance } from 'axios';
import * as fs from 'fs';
import * as https from 'https';
import { logger } from '../middleware/logger';

export interface SignedCertificate {
  certPem: string;
  chainPem: string;
  privateKeyPem: string;
  serialNumber: string;
  expiresAt: Date;
}

export interface CertificateRequest {
  commonName: string;
  organization: string;
  organizationalUnit?: string;
  country?: string;
  san?: string[];
  ttl?: string;
}

export type RevocationReason =
  | 'unspecified'
  | 'keyCompromise'
  | 'caCompromise'
  | 'affiliationChanged'
  | 'superseded'
  | 'cessationOfOperation';

const REVOCATION_CODES: Record<RevocationReason, number> = {
  unspecified: 0,
  keyCompromise: 1,
  caCompromise: 2,
  affiliationChanged: 3,
  superseded: 4,
  cessationOfOperation: 5,
};

export class CAService {
  private readonly client: AxiosInstance;

  constructor(
    private readonly caUrl: string,
    private readonly caFingerprint: string,
    private readonly provisionerName: string,
    private readonly provisionerPassphrase: string
  ) {
    const rootCaCert = fs.existsSync('/etc/ssl/step/root_ca.crt')
      ? fs.readFileSync('/etc/ssl/step/root_ca.crt')
      : undefined;

    this.client = axios.create({
      baseURL: caUrl,
      httpsAgent: new https.Agent({
        ca: rootCaCert,
        rejectUnauthorized: !!rootCaCert,
      }),
      timeout: 10_000,
    });
  }

  async sign(request: CertificateRequest): Promise<SignedCertificate> {
    logger.info({ msg: 'Requesting certificate from CA', cn: request.commonName });

    const csr = await this.generateCSR(request);
    const token = await this.getProvisionerToken(request.commonName);

    const response = await this.client.post('/1.0/sign', {
      csr,
      ott: token,
      notAfter: request.ttl ?? '2160h',
    });

    const { crt, ca } = response.data;
    const parsed = this.parseCertificate(crt);

    return {
      certPem: crt,
      chainPem: ca,
      privateKeyPem: response.data.key ?? '',
      serialNumber: parsed.serialNumber,
      expiresAt: parsed.notAfter,
    };
  }

  async revoke(serialNumber: string, reason: RevocationReason): Promise<void> {
    logger.info({ msg: 'Revoking certificate', serialNumber, reason });

    const token = await this.getProvisionerToken(serialNumber, true);

    await this.client.post('/1.0/revoke', {
      serial: serialNumber,
      ott: token,
      reasonCode: REVOCATION_CODES[reason],
      passive: false,
    });
  }

  async healthCheck(): Promise<boolean> {
    try {
      const resp = await this.client.get('/health');
      return resp.status === 200;
    } catch {
      return false;
    }
  }

  private async getProvisionerToken(subject: string, revoke = false): Promise<string> {
    const response = await this.client.post('/1.0/token', {
      subject,
      provisioner: this.provisionerName,
      passphrase: this.provisionerPassphrase,
      revoke,
    });
    return response.data.token as string;
  }

  private async generateCSR(request: CertificateRequest): Promise<string> {
    const forge = await import('node-forge');
    const keys = forge.pki.rsa.generateKeyPair(2048);
    const csr = forge.pki.createCertificationRequest();
    csr.publicKey = keys.publicKey;
    csr.setSubject([
      { name: 'commonName', value: request.commonName },
      { name: 'organizationName', value: request.organization },
      ...(request.organizationalUnit
        ? [{ name: 'organizationalUnitName', value: request.organizationalUnit }]
        : []),
      { name: 'countryName', value: request.country ?? 'BR' },
    ]);
    if (request.san?.length) {
      csr.setExtensions([{
        name: 'subjectAltName',
        altNames: request.san.map(dns => ({ type: 2, value: dns })),
      }]);
    }
    csr.sign(keys.privateKey, forge.md.sha256.create());
    return forge.pki.certificationRequestToPem(csr);
  }

  private parseCertificate(pem: string): { serialNumber: string; notAfter: Date } {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const forge = require('node-forge');
    const cert = forge.pki.certificateFromPem(pem);
    return {
      serialNumber: cert.serialNumber as string,
      notAfter: cert.validity.notAfter as Date,
    };
  }
}
