# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Clock
  class InboundWebhooksRetryJob < ClockJob
    def perform
      InboundWebhook.retriable.find_each do |inbound_webhook|
        InboundWebhooks::ProcessJob.perform_later(inbound_webhook:)
      end
    end
  end
end
