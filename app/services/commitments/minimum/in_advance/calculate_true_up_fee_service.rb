# frozen_string_literal: true

module Commitments
  module Minimum
    module InAdvance
      class CalculateTrueUpFeeService < Commitments::Minimum::CalculateTrueUpFeeService
        def amount_cents
          return 0 unless invoice_subscription.previous_invoice_subscription

          super
        end
      end
    end
  end
end
