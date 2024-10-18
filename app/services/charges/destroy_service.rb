# frozen_string_literal: true

module Charges
  class DestroyService < BaseService
    def initialize(charge:)
      @charge = charge

      super
    end

    def call
      return result.not_found_failure!(resource: 'charge') unless charge

      ActiveRecord::Base.transaction do
        charge.discard!
        charge.filter_values.discard_all
        charge.filters.discard_all

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
