// Shared error primitives for the catalog service.
//
// AppError  — thrown by service/repository layers to signal expected failures.
// toProblem — formats an error as an RFC 7807 problem-details object.

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
    type: `urn:catalog:error:${code.toLowerCase()}`,
    title: code,
    status: statusCode,
    detail,
    correlationId: correlationId ?? null,
  };
}
