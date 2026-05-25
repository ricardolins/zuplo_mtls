import { ZuploContext, ZuploRequest } from "@zuplo/runtime";

/**
 * API Key inbound policy for the certificate issuance bootstrap flow.
 *
 * Used ONLY on the certificate issuance endpoints (/v1/certificates POST/GET).
 * Partners receive their API Key from the Zuplo Developer Portal during sign-up.
 * Once they have an mTLS certificate, all subsequent calls use mtls-policy instead.
 */
export async function apiKeyInboundPolicy(
  request: ZuploRequest,
  context: ZuploContext,
  _policyName: string
): Promise<ZuploRequest | Response> {

  const apiKey = request.headers.get("X-API-Key")
    ?? request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");

  if (!apiKey) {
    return new Response(
      JSON.stringify({
        error: "API_KEY_REQUIRED",
        message: "Provide your API Key in the X-API-Key header. Obtain it from the Zuplo Developer Portal.",
      }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  // Validate the API Key against the Zuplo key store
  const keyData = await context.incomingRequestProperties.apiKeyService?.verifyKey(apiKey);

  if (!keyData || !keyData.isValid) {
    context.log.warn({ msg: "API Key validation failed", keyPrefix: apiKey.slice(0, 8) });
    return new Response(
      JSON.stringify({
        error: "INVALID_API_KEY",
        message: "Invalid or expired API Key. Visit the Developer Portal to manage your keys.",
      }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  const tenantId = keyData.metadata?.tenantId as string | undefined;

  if (!tenantId) {
    return new Response(
      JSON.stringify({ error: "KEY_NOT_BOUND", message: "API Key is not bound to a tenant." }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  // Inject tenant identity so the Certificate Service knows who is requesting
  request.headers.set("X-Tenant-Id", tenantId);
  request.headers.set("X-Auth-Method", "api-key");
  request.headers.set("X-Authenticated-Subject", keyData.metadata?.email as string ?? tenantId);

  context.log.info({ msg: "API Key authenticated", tenantId, subject: keyData.metadata?.email });

  return request;
}
