# frozen_string_literal: true

module Commitments
  module Minimum
    module InArrears
      class DatesService < Commitments::DatesService
        # NOTE: A downgraded subscription is billed for the period that just closed, not for the
        #       current one. `Subscriptions::DatesService#terminated_pay_in_arrears?` already makes
        #       that distinction when computing the invoice boundaries, and the commitment period
        #       has to be derived from the same period, otherwise the two disagree and the
        #       invoice_subscription of the billed period falls outside the commitment window.
        def current_usage
          subscription.terminated? && !subscription.downgraded?
        end

        private

        delegate :subscription, to: :invoice_subscription
      end
    end
  end
end
