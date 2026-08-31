const nodemailer = require('nodemailer');
const env = require('../config/env');

// With no SMTP host configured (the local-dev default), log the email
// instead of sending it, so registration/verification still works
// without a real mailbox.
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
