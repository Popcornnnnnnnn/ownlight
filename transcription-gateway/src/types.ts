export interface GatewayConfig {
  host: string;
  port: number;
  token: string;
  defaultModel: string;
  pythonPath: string;
  scriptPath: string;
  timeoutMs: number;
  maxFileBytes: number;
}

export interface TranscriptionSegment {
  start?: number | null;
  end?: number | null;
  text: string;
}

export interface TranscriptionRequest {
  filePath: string;
  fileName: string;
  mimeType: string;
  model: string;
  language?: string;
}

export interface TranscriptionResult {
  text: string;
  language?: string | null;
  segments?: TranscriptionSegment[];
  model?: string;
}

export type Transcriber = (request: TranscriptionRequest) => Promise<TranscriptionResult>;

export class TranscriptionGatewayError extends Error {
  readonly code: string;
  readonly statusCode: number;

  constructor(code: string, message: string, statusCode = 500) {
    super(message);
    this.name = "TranscriptionGatewayError";
    this.code = code;
    this.statusCode = statusCode;
  }
}
