import { ZuploContext, ZuploRequest } from "@zuplo/runtime";

interface Options {
  allowedIps: string[];
}

export async function ipAllowlistPolicy(
  request: ZuploRequest,
  context: ZuploContext,
  options: Options,
  _policyName: string
): Promise<ZuploRequest | Response> {
  // Cloudflare injects the real client IP here
  const clientIp =
    request.headers.get("CF-Connecting-IP") ??
    request.headers.get("X-Forwarded-For")?.split(",")[0]?.trim() ??
    "";

  const allowed = options.allowedIps.some((ip) => clientIp === ip);

  if (!allowed) {
    context.log.warn({ msg: "IP blocked", clientIp });
    return new Response(
      JSON.stringify({ error: "FORBIDDEN", message: "Access denied" }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  return request;
}
