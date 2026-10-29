type GithubOIDC = {
  iss: string;
  aud: string;
  sub: string;
  repository: string;
  repository_id: string;
  repository_owner: string;
  repository_owner_id: string;
  ref: string;
  ref_type: string;
};

type GithubOIDCResponse = {
  count: number;
  value: string;
};

type OIDCEnvironment = {
  requestToken: string;
  requestUrl: URL;
};

export default class Bootstrap {
  private static readonly AUDIENCE = "sts.amazonaws.com";

  public static async execute(): Promise<void> {
    try {
      const { requestToken, requestUrl } = this.verifyEnvironment();

      requestUrl.searchParams.set("audience", this.AUDIENCE);

      const response = await fetch(requestUrl, {
        method: "GET",
        headers: {
          Authorization: `Bearer ${requestToken}`,
        },
        signal: AbortSignal.timeout(10_000),
      });

      if (!response.ok) {
        throw new Error(
          `[OIDC][HTTP] Request failed with status ${response.status}`,
        );
      }

      const data: unknown = await response.json();
      const jwt = this.extractToken(data);
      const claims = this.decodePayload(jwt);

      console.log(JSON.stringify(claims, null, 2));
    } catch (error: unknown) {
      console.error(
        "[OIDC][ERROR]",
        error instanceof Error ? error.message : String(error),
      );

      process.exitCode = 1;
    }
  }

  private static verifyEnvironment(): OIDCEnvironment {
    const requestToken = process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN;

    const requestUrl = process.env.ACTIONS_ID_TOKEN_REQUEST_URL;

    if (!requestToken?.trim()) {
      throw new Error("[OIDC][ENV] ACTIONS_ID_TOKEN_REQUEST_TOKEN is missing");
    }

    if (!requestUrl?.trim()) {
      throw new Error("[OIDC][ENV] ACTIONS_ID_TOKEN_REQUEST_URL is missing");
    }

    const url = new URL(requestUrl);

    if (url.protocol !== "https:") {
      throw new Error("[OIDC][ENV] Request URL must use HTTPS");
    }

    return {
      requestToken,
      requestUrl: url,
    };
  }

  private static extractToken(data: unknown): string {
    if (
      typeof data !== "object" ||
      data === null ||
      !("value" in data) ||
      typeof data.value !== "string" ||
      !data.value
    ) {
      throw new Error("[OIDC][RESPONSE] Missing JWT value");
    }

    return data.value;
  }

  private static decodePayload(jwt: string): GithubOIDC {
    const segments = jwt.split(".");

    if (segments.length !== 3 || !segments[1]) {
      throw new Error("[OIDC][JWT] Invalid JWT structure");
    }

    const decoded = Buffer.from(segments[1], "base64url").toString("utf8");

    const payload: unknown = JSON.parse(decoded);

    if (
      typeof payload !== "object" ||
      payload === null ||
      !("sub" in payload) ||
      typeof payload.sub !== "string" ||
      !("aud" in payload) ||
      payload.aud !== this.AUDIENCE
    ) {
      throw new Error("[OIDC][JWT] Invalid claims");
    }

    return payload as GithubOIDC;
  }
}
