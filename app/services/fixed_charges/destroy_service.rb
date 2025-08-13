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

      fixed_charge.discard!
      result.fixed_charge = fixed_charge

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    rescue Discard::RecordNotDiscarded => e
      result.service_failure!(code: "fixed_charge_already_deleted", message: e.message)
    end

    private

    attr_reader :fixed_charge
  end
end
