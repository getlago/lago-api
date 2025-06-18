# frozen_string_literal: true

module FixedCharges
  class DestroyService < BaseService
    Result = BaseResult[:fixed_charge]

    def initialize(fixed_charge:)
      @fixed_charge = fixed_charge

      super
    end

    def call
      return result.not_found_failure!(resource: "fixed_charge") unless fixed_charge

      ActiveRecord::Base.transaction do
        fixed_charge.discard!

        deleted_at = Time.current
        # rubocop:disable Rails/SkipsModelValidations
        fixed_charge.properties.update_all(deleted_at:)
        # rubocop:enable Rails/SkipsModelValidations

        result.fixed_charge = fixed_charge
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :fixed_charge
  end
end
