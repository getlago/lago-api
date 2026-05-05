# frozen_string_literal: true

module Clock
  class ResetSlowWebhookEndpointsJob < ClockJob
    def perform
      WebhookEndpoint.where(slow_response: true).update_all(slow_response: false) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
