import { buildGatewayApp } from "./app.js";
import { loadGatewayConfig } from "./config.js";
import { createMlxWhisperTranscriber } from "./mlx-transcriber.js";

async function main(): Promise<void> {
  const config = loadGatewayConfig();
  if (!config.token) {
    throw new Error("TRANSCRIPTION_GATEWAY_TOKEN is required.");
  }

  const app = buildGatewayApp({
    config,
    transcribe: createMlxWhisperTranscriber(config)
  });

  await app.listen({
    host: config.host,
    port: config.port
  });
  console.log(
    `Private Moments transcription gateway listening on http://${config.host}:${config.port} (${config.defaultModel})`
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
