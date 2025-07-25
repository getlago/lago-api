# frozen_string_literal: true

module Webhooks
  module Subscriptions
    class UpdatedService < BaseService
      private

      def webhook_type
        "subscription.updated"
      end
    end
  end
end
