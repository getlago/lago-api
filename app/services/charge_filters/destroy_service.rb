# frozen_string_literal: true

module ChargeFilters
  class DestroyService < BaseService
    Result = BaseResult[:charge_filter]

    def initialize(charge_filter:)
      @charge_filter = charge_filter

      super
    end

    def call
      return result.not_found_failure!(resource: "charge_filter") unless charge_filter

      ActiveRecord::Base.transaction do
        charge_filter.values.update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        charge_filter.discard!

        result.charge_filter = charge_filter
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :charge_filter
  end
end
