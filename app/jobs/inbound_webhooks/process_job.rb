# frozen_string_literal: true

module InboundWebhooks
  class ProcessJob < ApplicationJob
    queue_as :default

    def perform(inbound_webhook:)
      InboundWebhooks::ProcessService.call(inbound_webhook:).raise_if_error!
    end
  end
end
