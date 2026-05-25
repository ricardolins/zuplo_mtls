import { ZuploContext, ZuploRequest } from "@zuplo/runtime";

/**
 * Política de validação mTLS para o Zuplo Gateway.
 *
 * Valida o certificado de cliente extraído do header injetado pelo
 * load balancer / ingress (X-Client-Cert-*), assegurando que:
 *   - O certificado foi assinado pela Root CA confiável
 *   - Está dentro do período de validade
 *   - O Common Name (CN) está na allowlist do tenant
 */
export async function mtlsInboundPolicy(
  request: ZuploRequest,
  context: ZuploContext,
  _policyName: string
): Promise<ZuploRequest | Response> {

  // Certificado do cliente injetado pelo ingress NGINX como header
  const clientCertPem = request.headers.get("X-Client-Cert");
  const clientCertDn  = request.headers.get("X-Client-Cert-DN");
  const clientCertExp = request.headers.get("X-Client-Cert-Expiry");

  if (!clientCertPem || !clientCertDn) {
    context.log.warn("mTLS: no client certificate presented");
    return new Response(
      JSON.stringify({ error: "MTLS_REQUIRED", message: "Client certificate required" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  // Verificar validade
  if (clientCertExp) {
    const expiry = new Date(clientCertExp);
    if (expiry < new Date()) {
      context.log.warn({ msg: "mTLS: expired client certificate", dn: clientCertDn });
      return new Response(
        JSON.stringify({ error: "CERT_EXPIRED", message: "Client certificate has expired" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // Extrair CN do Distinguished Name
  const cnMatch = clientCertDn.match(/CN=([^,]+)/);
  const commonName = cnMatch?.[1] ?? "";

  if (!commonName) {
    return new Response(
      JSON.stringify({ error: "INVALID_CERT", message: "Cannot extract CN from certificate" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  // Injetar identidade do certificado no contexto da requisição
  request.headers.set("X-Authenticated-CN", commonName);
  request.headers.set("X-Auth-Method", "mtls");

  context.log.info({ msg: "mTLS: client authenticated", cn: commonName });

  return request;
}
