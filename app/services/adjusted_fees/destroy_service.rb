# frozen_string_literal: true

module AdjustedFees
  class DestroyService < BaseService
    def initialize(fee:)
      @fee = fee

      super
    end

    def call
      return result.not_found_failure!(resource: 'fee') unless fee
      return result.not_found_failure!(resource: 'adjusted_fee') unless fee.adjusted_fee

      fee.adjusted_fee.destroy!

      result.fee = fee
      result
    end

    private

    attr_reader :fee
  end
end
