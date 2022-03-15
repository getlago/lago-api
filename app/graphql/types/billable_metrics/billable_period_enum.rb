# frozen_string_literal: true

module Types
  module BillableMetrics
    class BillablePeriodEnum < Types::BaseEnum
      BillableMetric::BILLABLE_PERIODS.each do |period|
        value period
      end
    end
  end
end
