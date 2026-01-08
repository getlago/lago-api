# frozen_string_literal: true

module ChargeFilters
  class DestroyService < BaseService
    include CascadeUpdatable

    Result = BaseResult[:charge_filter]

    def initialize(charge_filter:, cascade_updates: false)
      @charge_filter = charge_filter
      @cascade_updates = cascade_updates

      super
    end

    def call
      return result.not_found_failure!(resource: "charge_filter") unless charge_filter

      old_filters_attrs = capture_old_filters_attrs

      ActiveRecord::Base.transaction do
        charge_filter.values.update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        charge_filter.discard!

        result.charge_filter = charge_filter
      end

      trigger_cascade(old_filters_attrs)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :charge_filter, :cascade_updates

    delegate :charge, to: :charge_filter
  end
end
