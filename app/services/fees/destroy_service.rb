# frozen_string_literal: true

module Fees
  class DestroyService < BaseService
    def initialize(fee:)
      @fee = fee

      super
    end

    def call
      return result.not_found_failure!(resource: 'fee') unless fee
      fee.discard!

      result.fee = fee
      result
    end

    private

    attr_reader :fee
  end
end
