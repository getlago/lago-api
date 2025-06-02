# frozen_string_literal: true

module Charges
  class DestroyService < BaseService
    Result = BaseResult[:charge]

    def initialize(charge:)
      @charge = charge

      super
    end

    def call
      return result.not_found_failure!(resource: "charge") unless charge

      ActiveRecord::Base.transaction do
        charge.discard!

        deleted_at = Time.current
        # rubocop:disable Rails/SkipsModelValidations
        charge.filter_values.update_all(deleted_at:)
        charge.filters.update_all(deleted_at:)
        # rubocop:enable Rails/SkipsModelValidations

        result.charge = charge
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :charge
  end
end
