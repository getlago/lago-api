# frozen_string_literal: true

module Fees
  class CreateTrueUpService < BaseService
    def initialize(fee:)
      @fee = fee
      @boundaries = OpenStruct.new(fee&.properties)

      super
    end

    def call
      return result unless fee
      return result if fee.amount_cents >= prorated_min_amount_cents

      true_up_fee = fee.dup.tap do |f|
        f.amount_cents = prorated_min_amount_cents - fee.amount_cents
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

    attr_reader :fee, :boundaries

    delegate :charge, :subscription, to: :fee

    def prorated_min_amount_cents
      from_date = boundaries.charges_from_datetime.to_date
      to_date = boundaries.charges_to_datetime.to_date

      # NOTE: number of days between beginning of the period and the termination date
      number_of_day_to_bill = (to_date + 1.day - from_date).to_i

      day_price * number_of_day_to_bill
    end

    def date_service
      @date_service ||= Subscriptions::DatesService.new_instance(
        subscription,
        subscription.terminated_at || Time.current,
      )
    end

    def day_price
      duration = date_service.compute_charges_duration(from_date: date_service.compute_charges_from_date)
      charge.min_amount_cents.fdiv(duration.to_i)
    end
  end
end
