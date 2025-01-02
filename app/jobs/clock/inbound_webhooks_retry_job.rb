# frozen_string_literal: true

module Clock
  class InboundWebhooksRetryJob < ApplicationJob
    include SentryCronConcern

    queue_as "clock"

    def perform
      InboundWebhook.retriable.find_each do |inbound_webhook|
        InboundWebhooks::ProcessJob.perform_later(inbound_webhook:)
      end
    end
  end
end
