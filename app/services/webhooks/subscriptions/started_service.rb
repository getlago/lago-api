# frozen_string_literal: true

module Webhooks
  module Subscriptions
    class StartedService < BaseService
      def webhook_type
        "subscription.started"
      end
    end
  end
end
