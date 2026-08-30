const { ApiError } = require('./errorHandler');

// Validates (and coerces/trims, per the schema) req.body against a zod
// schema, replacing req.body with the parsed result so handlers always
// see clean data. On failure, responds 400 with per-field messages
// instead of leaking a raw zod stack trace to the client.
function validateBody(schema) {
  return (req, res, next) => {
    const result = schema.safeParse(req.body);
    if (!result.success) {
      const details = result.error.issues.map((issue) => ({
        field: issue.path.join('.'),
        message: issue.message,
      }));
      return next(
        new ApiError(400, 'VALIDATION_ERROR', 'Invalid input.', details)
      );
    }
    req.body = result.data;
    next();
  };
}

// Same idea as validateBody, but for query-string params (e.g. GET
// /users/search?q=...) — req.query is always strings, so this is where
// trimming/length checks on a search term belong, not the controller.
function validateQuery(schema) {
  return (req, res, next) => {
    const result = schema.safeParse(req.query);
    if (!result.success) {
      const details = result.error.issues.map((issue) => ({
        field: issue.path.join('.'),
        message: issue.message,
      }));
      return next(
        new ApiError(400, 'VALIDATION_ERROR', 'Invalid input.', details)
      );
    }
    req.query = result.data;
    next();
  };
}

// Same idea again, for route params (e.g. the `:id` in POST
// /invitations/:id/accept) — without this, a malformed id reaches the
// database as a raw string and Postgres's "invalid input syntax for
// type uuid" surfaces as an opaque 500 instead of a clean 400.
function validateParams(schema) {
  return (req, res, next) => {
    const result = schema.safeParse(req.params);
    if (!result.success) {
      const details = result.error.issues.map((issue) => ({
        field: issue.path.join('.'),
        message: issue.message,
      }));
      return next(
        new ApiError(400, 'VALIDATION_ERROR', 'Invalid input.', details)
      );
    }
    req.params = result.data;
    next();
  };
}

module.exports = { validateBody, validateQuery, validateParams };
