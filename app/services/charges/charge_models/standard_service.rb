# frozen_string_literal: true

module Charges
  module ChargeModels
    class StandardService < Charges::ChargeModels::BaseService
      protected

      def compute_amount(value)
        (value * charge.properties['amount_cents']).to_i
      end
    end
  end
end
