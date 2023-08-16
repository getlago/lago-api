# frozen_string_literal: true

module Fees
  class CreateTrueUpService < BaseService
    def initialize(fee:, amount_cents:)
      @fee = fee
      @amount_cents = amount_cents
      @boundaries = OpenStruct.new(fee&.properties)

      super
    end

    def call
      return result unless fee
      return result if amount_cents >= prorated_min_amount_cents

      true_up_fee = fee.dup.tap do |f|
        f.amount_cents = prorated_min_amount_cents - amount_cents
        f.units = 1
        f.events_count = 0
        f.group_id = nil
        f.true_up_parent_fee = fee
      end

      result.true_up_fee = true_up_fee
      result
    end

    private

    attr_reader :fee, :amount_cents, :boundaries

    delegate :charge, :subscription, to: :fee

    def prorated_min_amount_cents
      # NOTE: number of days between beginning of the period and the termination date
      from_datetime = boundaries.charges_from_datetime.to_time
      to_datetime = boundaries.charges_to_datetime.to_time
      number_of_day_to_bill = (to_datetime - from_datetime).fdiv(1.day).ceil

      date_service.charge_single_day_price(charge:) * number_of_day_to_bill
    end

    def date_service
      boundaries.timestamp = Time.zone.at(boundaries.timestamp) if boundaries.timestamp.is_a?(Integer)

      @date_service ||= Subscriptions::DatesService.new_instance(
        subscription,
        boundaries.timestamp || Time.current,
        current_usage: subscription.terminated? && subscription.upgraded?,
      )
    end
  end
end
