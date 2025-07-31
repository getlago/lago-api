# frozen_string_literal: true

module Webhooks
  module Subscriptions
    class TrialEndedService < BaseService
      private

      def webhook_type
        "subscription.trial_ended"
      end
    end
  end
end
