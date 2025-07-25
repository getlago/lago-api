# frozen_string_literal: true

module Webhooks
  module Subscriptions
    class TerminatedService < BaseService
      private

      def webhook_type
        "subscription.terminated"
      end
    end
  end
end
