/**
 * Exemplo de cliente Node.js com mTLS para o Zuplo Gateway.
 * Execute: npx ts-node mtls-client.ts
 */
import * as https from 'https';
import * as fs from 'fs';
import * as path from 'path';

const GATEWAY_URL   = process.env.GATEWAY_URL   ?? 'https://api.zuplo.baas.io';
const CERT_SERVICE  = process.env.CERT_SERVICE  ?? 'https://certs.baas.io';
const TENANT_ID     = process.env.TENANT_ID     ?? 'meu-uuid-tenant';
const CERT_PATH     = process.env.CERT_PATH     ?? './certs-output/client.crt';
const KEY_PATH      = process.env.KEY_PATH      ?? './certs-output/client.key';
const CA_PATH       = process.env.CA_PATH       ?? './certs-output/root_ca.crt';

// Agente HTTPS com mTLS configurado
function createMtlsAgent(): https.Agent {
  return new https.Agent({
    cert: fs.readFileSync(path.resolve(CERT_PATH)),
    key:  fs.readFileSync(path.resolve(KEY_PATH)),
    ca:   fs.existsSync(path.resolve(CA_PATH))
          ? fs.readFileSync(path.resolve(CA_PATH))
          : undefined,
    rejectUnauthorized: true,
  });
}

async function issueCertificate(): Promise<void> {
  console.log('\n=== Emitindo certificado mTLS ===');
  const response = await fetch(`${CERT_SERVICE}/v1/certificates`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Tenant-Id': TENANT_ID,
    },
    body: JSON.stringify({
      commonName:   'parceiro-a.api.baas.io',
      organization: 'Parceiro Financeiro A Ltda',
      country:      'BR',
      ttl:          '2160h',
    }),
  });

  const cert = await response.json();
  console.log('Certificado emitido:', {
    id:        cert.id,
    cn:        cert.commonName,
    expiresAt: cert.expiresAt,
    status:    cert.status,
  });

  // Salvar arquivos localmente
  fs.mkdirSync('./certs-output', { recursive: true });
  fs.writeFileSync('./certs-output/client.crt', cert.certPem);
  fs.writeFileSync('./certs-output/client.key', cert.privateKeyPem, { mode: 0o600 });
  fs.writeFileSync('./certs-output/chain.crt',  cert.chainPem);
  console.log('Arquivos salvos em ./certs-output/');
}

async function callProtectedApi(): Promise<void> {
  console.log('\n=== Chamando API protegida via mTLS ===');

  const agent = createMtlsAgent();

  const response = await fetch(`${GATEWAY_URL}/v1/certificates`, {
    // @ts-expect-error — Node 18+ aceita agent via undici
    dispatcher: agent,
    headers: {
      'Content-Type': 'application/json',
      'X-Tenant-Id':  TENANT_ID,
    },
  });

  if (!response.ok) {
    console.error('Erro:', response.status, await response.text());
    return;
  }

  const data = await response.json();
  console.log('Resposta:', JSON.stringify(data, null, 2));
}

async function main(): Promise<void> {
  try {
    if (!fs.existsSync(CERT_PATH)) {
      await issueCertificate();
    }
    await callProtectedApi();
  } catch (err) {
    console.error('Erro:', err);
    process.exit(1);
  }
}

main();
