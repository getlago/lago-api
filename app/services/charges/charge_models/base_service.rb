# frozen_string_literal: true

module Charges
  module ChargeModels
    class BaseService < ::BaseService
      def initialize(charge:)
        super(nil)
        @charge = charge
      end

      def apply(value:)
        result.units = value
        result.amount = compute_amount(value)
        result
      end

      protected

      attr_accessor :charge

      def compute_amount(value)
        raise NotImplementedError
      end
    end
  end
end
