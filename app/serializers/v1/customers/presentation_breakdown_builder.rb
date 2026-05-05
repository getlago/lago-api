# frozen_string_literal: true

module V1
  module Customers
    class PresentationBreakdownBuilder
      ALL = :all
      UNGROUPED = :ungrouped
      GROUPED = :grouped

      def self.call(fees, filter:)
        new(fees, filter:).call
      end

      def initialize(fees, filter:)
        @fees = fees
        @filter = filter
      end

      def call
        Array(fees).flat_map do |fee|
          next [] if filter == UNGROUPED && fee.grouped_by.present?
          next [] if filter == GROUPED && fee.grouped_by.blank?

          fee.presentation_breakdowns.map do |breakdown|
            {
              presentation_by: breakdown.presentation_by,
              units: breakdown.units.to_s
            }
          end
        end
      end

      private

      attr_reader :fees, :filter
    end
  end
end
