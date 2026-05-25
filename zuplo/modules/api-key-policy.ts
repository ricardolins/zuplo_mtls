import { ZuploContext, ZuploRequest } from "@zuplo/runtime";

/**
 * Runs AFTER Zuplo's built-in api-key-inbound policy.
 * That policy validates the key; this one extracts tenant metadata
 * from request.user and injects it as headers for the Certificate Service.
 */
export async function apiKeyInboundPolicy(
  request: ZuploRequest,
  context: ZuploContext,
  _policyName: string
): Promise<ZuploRequest | Response> {
  const user = request.user;

  if (!user) {
    return new Response(
      JSON.stringify({
        error: "API_KEY_REQUIRED",
        message:
          "Provide your API Key in the X-API-Key header. Obtain it from the Zuplo Developer Portal.",
      }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  const tenantId =
    (user.data?.tenantId as string | undefined) ?? user.sub ?? "";

  if (!tenantId) {
    return new Response(
      JSON.stringify({
        error: "KEY_NOT_BOUND",
        message: "API Key is not bound to a tenant.",
      }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  // Inject tenant identity so the Certificate Service knows who is requesting
  request.headers.set("X-Tenant-Id", tenantId);
  request.headers.set("X-Auth-Method", "api-key");
  request.headers.set(
    "X-Authenticated-Subject",
    (user.data?.email as string | undefined) ?? tenantId
  );

  context.log.info({ msg: "API Key authenticated", tenantId });

  return request;
}
