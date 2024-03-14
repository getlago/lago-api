# frozen_string_literal: true

module Commitments
  module Minimum
    module InArrears
      class DatesService < Commitments::HelperService
        def call
          ds = Subscriptions::DatesService.new_instance(
            subscription,
            invoice_subscription.timestamp,
            current_usage: subscription.terminated?,
          )

          return ds unless subscription.terminated?

          Subscriptions::TerminatedDatesService.new(
            subscription:,
            invoice: invoice_subscription.invoice,
            date_service: ds,
          ).call
        end
      end
    end
  end
end
