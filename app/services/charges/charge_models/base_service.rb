# frozen_string_literal: true

module Charges
  module ChargeModels
    class BaseService < ::BaseService
      def self.apply(...)
        new(...).apply
      end

      def initialize(charge:, aggregation_result:, properties:)
        super(nil)
        @charge = charge
        @aggregation_result = aggregation_result
        @properties = properties
      end

      def apply
        result.units = aggregation_result.aggregation
        result.count = aggregation_result.count
        result.amount = compute_amount
        result
      end

      protected

      attr_accessor :charge, :aggregation_result, :properties

      delegate :units, to: :result

      def compute_amount
        raise NotImplementedError
      end
    end
  end
end
