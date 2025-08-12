# frozen_string_literal: true

module Webhooks
  module Subscriptions
    class TerminationAlertService < BaseService
      private

      def webhook_type
        "subscription.termination_alert"
      end
    end
  end
end
