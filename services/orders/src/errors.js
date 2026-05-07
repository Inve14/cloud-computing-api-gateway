export class AppError extends Error {
  constructor(statusCode, code, detail) {
    super(detail);
    this.statusCode = statusCode;
    this.code = code;
    this.detail = detail;
  }
}

export function toProblem(statusCode, code, detail, correlationId) {
  return {
    type: `urn:orders:error:${code.toLowerCase()}`,
    title: code,
    status: statusCode,
    detail,
    correlationId: correlationId ?? null,
  };
}
