// Central error shape for the whole API: { error: { code, message, details? } }.
// Route handlers should `throw` an ApiError (or let unexpected errors
// bubble up) and let this middleware turn it into a response, instead of
// each route inventing its own error JSON shape.

class ApiError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

// Wraps an async route handler so a rejected promise reaches Express's
// error handling instead of becoming an unhandled rejection.
function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

function notFoundHandler(req, res, next) {
  next(new ApiError(404, 'NOT_FOUND', `No route: ${req.method} ${req.path}`));
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  if (err instanceof ApiError) {
    return res.status(err.status).json({
      error: { code: err.code, message: err.message, details: err.details },
    });
  }

  // Postgres unique-violation, surfaced generically in case a route forgot
  // to check for a duplicate before inserting.
  if (err.code === '23505') {
    return res.status(409).json({
      error: { code: 'CONFLICT', message: 'Resource already exists.' },
    });
  }

  // The database itself is unreachable — 503 tells the client this is
  // transient and worth retrying, instead of a generic 500.
  if (
    ['ECONNREFUSED', 'ETIMEDOUT', 'ENOTFOUND'].includes(err.code) ||
    /connection.*terminated/i.test(err.message || '')
  ) {
    console.error('Database unavailable:', err);
    return res.status(503).json({
      error: {
        code: 'SERVICE_UNAVAILABLE',
        message: 'The service is temporarily unavailable. Please try again shortly.',
      },
    });
  }

  // multer's own error class for upload problems (as opposed to ones
  // we raise via fileFilter, already handled above as ApiErrors).
  if (err.name === 'MulterError') {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(400).json({
        error: { code: 'FILE_TOO_LARGE', message: 'File exceeds the maximum allowed size.' },
      });
    }
    return res.status(400).json({
      error: { code: 'UPLOAD_ERROR', message: err.message },
    });
  }

  console.error('Unhandled error:', err);
  return res.status(500).json({
    error: { code: 'INTERNAL_ERROR', message: 'Something went wrong.' },
  });
}

module.exports = { ApiError, asyncHandler, notFoundHandler, errorHandler };
