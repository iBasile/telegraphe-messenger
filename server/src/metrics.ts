export class Metrics {
  public activeConnections = 0;
  public deliveredMessages = 0;
  public deliveryLatencySeconds = 0;

  public render(mailboxSize: number): string {
    return [
      '# HELP telegraphe_active_connections Active WebSocket connections.',
      '# TYPE telegraphe_active_connections gauge',
      `telegraphe_active_connections ${this.activeConnections}`,
      '# HELP telegraphe_delivery_latency_seconds Message delivery latency in seconds.',
      '# TYPE telegraphe_delivery_latency_seconds summary',
      `telegraphe_delivery_latency_seconds_sum ${this.deliveryLatencySeconds}`,
      `telegraphe_delivery_latency_seconds_count ${this.deliveredMessages}`,
      '# HELP telegraphe_mailbox_size Pending mailbox messages.',
      '# TYPE telegraphe_mailbox_size gauge',
      `telegraphe_mailbox_size ${mailboxSize}`,
      '',
    ].join('\n');
  }
}
