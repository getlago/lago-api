# frozen_string_literal: true

module Commitments
  module Minimum
    module InAdvance
      class HelperService < Commitments::HelperService
        def dates_service
          ds = Subscriptions::DatesService.new_instance(
            subscription,
            invoice_subscription.timestamp,
            current_usage: true,
          )

          return ds unless subscription.terminated?

          Invoices::CalculateFeesService.new(invoice: invoice_subscription.invoice)
            .terminated_date_service(subscription, ds)
        end
      end
    end
  end
end
