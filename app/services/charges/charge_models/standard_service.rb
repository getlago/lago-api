# frozen_string_literal: true

module Charges
  module ChargeModels
    class StandardService < Charges::ChargeModels::BaseService
      def apply(value:)
        result.amount_cents = (value * charge.amount_cents).to_i
        result
      end
    end
  end
end
