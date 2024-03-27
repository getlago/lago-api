# frozen_string_literal: true

module Charges
  module ChargeModels
    class GroupedStandardService < BaseService
      def self.apply(...)
        new(...).apply
      end

      def initialize(charge:, aggregation_result:, properties:)
        super

        @charge = charge
        @aggregation_result = aggregation_result
        @properties = properties
      end

      def apply
        result.grouped_results = aggregation_result.aggregations.map do |aggregation|
          group_result = Charges::ChargeModels::StandardService.apply(
            charge:,
            aggregation_result: aggregation,
            properties:
          )
          group_result.grouped_by = aggregation.grouped_by
          group_result
        end

        result
      end

      protected

      attr_accessor :charge, :aggregation_result, :properties
    end
  end
end
