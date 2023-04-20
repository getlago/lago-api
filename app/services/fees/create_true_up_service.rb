# frozen_string_literal: true

module Fees
  class CreateTrueUpService < BaseService
    def initialize(fee:)
      @fee = fee
      super
    end

    def call
      return result unless fee
      return result if fee.amount_cents >= charge.min_amount_cents

      true_up_fee = fee.dup.tap do |f|
        f.amount_cents = charge.min_amount_cents - fee.amount_cents
        f.units = 1
        f.events_count = 0
        f.group_id = nil
      end
      true_up_fee.compute_vat

      fee.true_up_fee = true_up_fee
      result.true_up_fee = true_up_fee
      result
    end

    private

    attr_reader :fee

    delegate :charge, to: :fee
  end
end
