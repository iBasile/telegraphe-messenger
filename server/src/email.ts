import nodemailer from 'nodemailer';
import type { Config } from './config.js';
export interface EmailSender {
  send(to: string, subject: string, text: string): Promise<void>;
}
export class ConsoleEmailSender implements EmailSender {
  async send(to: string, subject: string, text: string): Promise<void> {
    void text;
    console.info(JSON.stringify({ event: 'email_sent', to, subject }));
  }
}
export class SmtpEmailSender implements EmailSender {
  private readonly transport: nodemailer.Transporter;
  constructor(private readonly cfg: Config) {
    this.transport = nodemailer.createTransport({
      host: cfg.SMTP_HOST,
      port: cfg.SMTP_PORT,
      secure: cfg.SMTP_PORT === 465,
      auth: cfg.SMTP_USER ? { user: cfg.SMTP_USER, pass: cfg.SMTP_PASSWORD } : undefined,
    });
  }
  async send(to: string, subject: string, text: string): Promise<void> {
    await this.transport.sendMail({ from: this.cfg.EMAIL_FROM, to, subject, text });
  }
}
export const createEmailSender = (cfg: Config): EmailSender =>
  cfg.EMAIL_MODE === 'smtp' ? new SmtpEmailSender(cfg) : new ConsoleEmailSender();
