# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module InboundWebhooks
  class ProcessJob < ApplicationJob
    queue_as :default

    def perform(inbound_webhook:)
      InboundWebhooks::ProcessService.call!(inbound_webhook:)
    end
  end
end
