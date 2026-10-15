# frozen_string_literal: true

module Commitments
  module Minimum
    module InArrears
      class DatesService < Commitments::DatesService
        # Downgraded subscriptions are billed AFTER the end of the billing period,
        # so the dates are calculated for the previous billing period, not the current one.
        def current_usage
          subscription.terminated? && !subscription.downgraded?
        end

        private

        delegate :subscription, to: :invoice_subscription
      end
    end
  end
end
