/* eslint-disable camelcase */

// Each user's X25519 identity public key, used for end-to-end
// encryption. Stored as plain text — a public key isn't sensitive.
// Nullable because it's registered by the client on first login after
// this migration ships, not at account creation.
exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.addColumn('users', {
    public_key: { type: 'text' },
  });
};

exports.down = (pgm) => {
  pgm.dropColumn('users', 'public_key');
};
