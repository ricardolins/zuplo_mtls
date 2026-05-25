import { ZuploContext, ZuploRequest } from "@zuplo/runtime";

interface PolicyOptions {
  /** Lista de CNs autorizados. Vazio = qualquer CN válido é aceito. */
  allowedCommonNames?: string[];
  /** Verificar OCSP em tempo real */
  checkOcsp?: boolean;
  /** URL do endpoint OCSP da CA */
  ocspUrl?: string;
}

/**
 * Política de validação adicional do certificado cliente.
 * Executada após mtls-policy — verifica CN allowlist e OCSP.
 */
export async function certValidationPolicy(
  request: ZuploRequest,
  context: ZuploContext,
  _policyName: string,
  options: PolicyOptions = {}
): Promise<ZuploRequest | Response> {

  const cn = request.headers.get("X-Authenticated-CN");

  if (!cn) {
    return new Response(
      JSON.stringify({ error: "CERT_NOT_VALIDATED", message: "Run mtls-policy before cert-validation-policy" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // Verificar CN contra allowlist
  if (options.allowedCommonNames && options.allowedCommonNames.length > 0) {
    const allowed = options.allowedCommonNames.some(pattern => {
      if (pattern.startsWith("*.")) {
        const domain = pattern.slice(2);
        return cn.endsWith(`.${domain}`) || cn === domain;
      }
      return cn === pattern;
    });

    if (!allowed) {
      context.log.warn({ msg: "mTLS: CN not in allowlist", cn });
      return new Response(
        JSON.stringify({ error: "CERT_NOT_AUTHORIZED", message: `CN '${cn}' is not authorized` }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // Verificação OCSP opcional
  if (options.checkOcsp && options.ocspUrl) {
    const ocspResult = await checkOcspStatus(
      request.headers.get("X-Client-Cert-Serial") ?? "",
      options.ocspUrl,
      context
    );
    if (ocspResult === "revoked") {
      context.log.warn({ msg: "mTLS: certificate revoked (OCSP)", cn });
      return new Response(
        JSON.stringify({ error: "CERT_REVOKED", message: "Client certificate has been revoked" }),
        { status: 401, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  return request;
}

async function checkOcspStatus(
  serial: string,
  ocspUrl: string,
  context: ZuploContext
): Promise<"good" | "revoked" | "unknown"> {
  if (!serial) return "unknown";
  try {
    const resp = await fetch(`${ocspUrl}/${serial}`, {
      headers: { Accept: "application/ocsp-response" },
      signal: AbortSignal.timeout(3000),
    });
    if (!resp.ok) return "unknown";
    const data = await resp.json() as { status: string };
    return (data.status as "good" | "revoked" | "unknown") ?? "unknown";
  } catch (err) {
    context.log.warn({ msg: "OCSP check failed, allowing request", error: String(err) });
    return "unknown";
  }
}
