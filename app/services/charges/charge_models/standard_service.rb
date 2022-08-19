# frozen_string_literal: true

module Charges
  module ChargeModels
    class StandardService < Charges::ChargeModels::BaseService
      protected

      def compute_amount
        (units * BigDecimal(charge.properties['amount']))
      end
    end
  end
end
