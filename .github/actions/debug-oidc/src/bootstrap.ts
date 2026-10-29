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

export default class Bootstrap {
  private static ACTIONS_ID_TOKEN_REQUEST_TOKEN: string;
  private static ACTIONS_ID_TOKEN_REQUEST_URL: string;

  public static async execute() {
    try {
      this.verifyEnvironment();

      const response = await fetch(
        this.ACTIONS_ID_TOKEN_REQUEST_URL + "&audience=sts.amazonaws.com",
        {
          headers: {
            Authorization: "Bearer " + this.ACTIONS_ID_TOKEN_REQUEST_TOKEN,
          },
        },
      );

      if (!response.ok) {
        throw new Error(
          `[GET][ERROR] Github Error 
         [STATUS] : ${response.status}`,
        );
      }

      const data = (await response.json()) as string;

      console.log(data);

      const [_, encryptedOIDCToken] = data.split(".");

      if (!encryptedOIDCToken) {
        throw new Error("[JWT][PAYLOAD][ERROR] The token has empty payload");
      }

      const token: GithubOIDC = JSON.parse(
        Buffer.from(encryptedOIDCToken, "base64url").toString(),
      );

      console.log(JSON.stringify(token), null, "2");
    } catch (err: unknown) {
      if (err instanceof Error) {
        console.error(err.message);
      }
    }
  }

  private static verifyEnvironment(): void {
    if (
      process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN == null ||
      process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN.length == 0
    ) {
      throw new Error("ACTION_ID_TOKEN_REQUEST_TOKEN is empty");
    }

    if (
      process.env.ACTIONS_ID_TOKEN_REQUEST_URL == null ||
      process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN.length == 0
    ) {
      throw new Error("ACTIONS_ID_TOKEN_REQUEST_URL is empty");
    }

    this.ACTIONS_ID_TOKEN_REQUEST_TOKEN =
      process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN;
    this.ACTIONS_ID_TOKEN_REQUEST_URL =
      process.env.ACTIONS_ID_TOKEN_REQUEST_URL;
  }
}
