export class LinxAppError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LinxAppError';
  }
}

export class LinxAuthExpiredError extends LinxAppError {
  readonly authExpired = true;

  constructor(message = 'LinX Cloud login expired.') {
    super(message);
    this.name = 'LinxAuthExpiredError';
  }
}

export class LinxHTTPError extends LinxAppError {
  readonly authExpired: boolean;

  constructor(
    message: string,
    readonly status: number,
    readonly responseBody: string,
  ) {
    super(message);
    this.name = 'LinxHTTPError';
    this.authExpired = isInvalidSolidTokenResponse(status, responseBody);
  }
}

export function isInvalidSolidTokenResponse(
  status: number,
  responseBody: string,
): boolean {
  if (status !== 401) {
    return false;
  }

  const normalized = responseBody.toLowerCase();
  return (
    normalized.includes('invalid solid token') ||
    normalized.includes('unauthorized')
  );
}

export function isAuthExpiredError(error: unknown): boolean {
  if (error instanceof LinxAuthExpiredError) {
    return true;
  }
  if (
    typeof error === 'object' &&
    error !== null &&
    'authExpired' in error &&
    error.authExpired === true
  ) {
    return true;
  }

  const message = error instanceof Error ? error.message : String(error);
  const normalized = message.toLowerCase();
  return (
    normalized.includes('linx cloud login expired') ||
    normalized.includes('invalid refresh') ||
    normalized.includes('invalid_client') ||
    normalized.includes('invalid_grant')
  );
}
