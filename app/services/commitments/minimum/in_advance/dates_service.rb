# frozen_string_literal: true

module Commitments
  module Minimum
    module InAdvance
      class DatesService < Commitments::HelperService
        def call
          ds = Subscriptions::DatesService.new_instance(
            invoice_subscription.subscription,
            invoice_subscription.timestamp,
            current_usage: true,
          )

          return ds unless subscription.terminated?

          Subscriptions::TerminatedDatesService.new(
            subscription: invoice_subscription.subscription,
            invoice: invoice_subscription.invoice,
            date_service: ds,
          ).call
        end
      end
    end
  end
end
