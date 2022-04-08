# frozen_string_literal: true

module Charges
  module ChargeModels
    class StandardService < Charges::ChargeModels::BaseService
      def apply(value:)
        # TODO: return result object
        value * charge.amount_cents
      end
    end
  end
end
