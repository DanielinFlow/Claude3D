/**
 * Static checks for the upstream gateway URL a user types into the connect UI.
 *
 * Claw3D speaks the OpenClaw gateway protocol: the client opens a socket,
 * sends a `connect` frame, and waits for `hello-ok`. A URL that can never
 * succeed — like TLS against a port Tailscale serves as plain HTTP — turns
 * into a 13s connect timeout with no explanation. Catching it here turns
 * the timeout into an actionable message before the user hits Connect.
 */

export type UpstreamUrlFindingSeverity = "error" | "warning";

export type UpstreamUrlFinding = {
  code: string;
  severity: UpstreamUrlFindingSeverity;
  message: string;
  fix: string;
};

/** Ports Tailscale Serve can terminate TLS on. */
const TAILSCALE_TLS_PORTS = new Set(["443", "8443", "10000"]);

const isTailnetHostname = (hostname: string) =>
  hostname === "ts.net" || hostname.endsWith(".ts.net");

export const inspectUpstreamGatewayUrl = (
  rawUrl: unknown,
  _adapterType: unknown = ""
): UpstreamUrlFinding[] => {
  const url = typeof rawUrl === "string" ? rawUrl.trim() : "";
  if (!url) return [];

  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return [];
  }

  const findings: UpstreamUrlFinding[] = [];
  const protocol = parsed.protocol.toLowerCase();
  const hostname = parsed.hostname.toLowerCase();
  const port = parsed.port;

  if (protocol === "wss:" && port && !TAILSCALE_TLS_PORTS.has(port) && isTailnetHostname(hostname)) {
    findings.push({
      code: "tls_on_plain_tailnet_port",
      severity: "warning",
      message:
        `wss:// expects TLS, but Tailscale only terminates TLS on ports ${[...TAILSCALE_TLS_PORTS].join(", ")}. ` +
        `Port ${port} on a tailnet host is almost certainly plain HTTP.`,
      fix:
        "Either use ws:// against this port, or expose the gateway with " +
        "`tailscale serve --https=443 http://127.0.0.1:<port>` and connect to wss://<host> with no port.",
    });
  }

  return findings;
};

export const hasBlockingUpstreamUrlFinding = (findings: readonly UpstreamUrlFinding[]): boolean =>
  findings.some((finding) => finding.severity === "error");
