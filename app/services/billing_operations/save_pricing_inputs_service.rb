# frozen_string_literal: true

module BillingOperations
  class SavePricingInputsService < BaseService
    Result = BaseResult

    def initialize(operation:, segments:)
      @operation = operation
      @segments = segments
      super
    end

    def call
      return result if segments.empty?

      ActiveRecord::Base.transaction do
        operation.segments.destroy_all
        segments.each_with_index do |segment, position|
          operation.segments.create!(
            organization: operation.organization, position:,
            started_at: segment.started_at, ended_at: BillingSegment.exclusive_end(segment.ended_at),
            rate_card_rate: segment.rate_card_rate, rate_override: segment.rate_override,
            proration_ratio: segment.proration_ratio, rate_properties: segment.rate_properties,
            currency: segment.currency, pricing_unit: segment.pricing_unit,
            units: segment.units, prepaid_units: segment.prepaid_units, units_intervals: segment.units_intervals
          )
        end
      end
      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    end

    private

    attr_reader :operation, :segments
  end
end
