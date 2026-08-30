const nodemailer = require('nodemailer');
const env = require('../config/env');

// With no SMTP host configured (the default for local dev — see
// .env.example), fall back to logging the email instead of sending it.
// This keeps registration/verification working out of the box without
// requiring a real mailbox for every contributor.
const transporter = env.smtpHost
  ? nodemailer.createTransport({
      host: env.smtpHost,
      port: env.smtpPort,
      secure: env.smtpPort === 465,
      auth: env.smtpUser ? { user: env.smtpUser, pass: env.smtpPass } : undefined,
    })
  : null;

async function sendEmail({ to, subject, text, html }) {
  if (!transporter) {
    console.log(`[email:dev-mode] To: ${to} | Subject: ${subject}\n${text}`);
    return;
  }
  await transporter.sendMail({ from: env.smtpFrom, to, subject, text, html });
}

module.exports = { sendEmail };
