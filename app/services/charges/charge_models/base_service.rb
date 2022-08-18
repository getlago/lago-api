# frozen_string_literal: true

module Charges
  module ChargeModels
    class BaseService < ::BaseService
      def self.apply(...)
        new(...).apply
      end

      def initialize(charge:, aggregation_result:)
        super(nil)
        @charge = charge
        @aggregation_result = aggregation_result
      end

      def apply
        result.units = aggregation_result.aggregation
        result.count = aggregation_result.count
        result.amount = compute_amount
        result
      end

      protected

      attr_accessor :charge, :aggregation_result

      delegate :units, to: :result

      def compute_amount(value)
        raise NotImplementedError
      end
    end
  end
end
