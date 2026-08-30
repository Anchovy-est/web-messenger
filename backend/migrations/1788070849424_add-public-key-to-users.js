/* eslint-disable camelcase */

// Each user's long-term X25519 identity public key, used for end-to-end
// message/media encryption — see docs/ENCRYPTION.md.
// A public key is, by definition, not sensitive (that's the entire point
// of asymmetric crypto), so it's stored as plain text same as any other
// public profile field — nothing here needs at-rest encryption. Nullable
// because it's registered by the client on first login/registration
// *after* this migration ships, not at account-creation time — an
// existing user's row starts out with no key until their app next runs.
exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.addColumn('users', {
    public_key: { type: 'text' },
  });
};

exports.down = (pgm) => {
  pgm.dropColumn('users', 'public_key');
};
