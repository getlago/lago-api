# frozen_string_literal: true

module Fees
  class CreateTrueUpService < BaseService
    def initialize(fee:, used_amount_cents:, used_precise_amount_cents:)
      @fee = fee
      @used_amount_cents = used_amount_cents
      @used_precise_amount_cents = used_precise_amount_cents
      @boundaries = OpenStruct.new(fee&.properties)

      super
    end

    def call
      return result unless fee
      return result if used_amount_cents >= prorated_min_amount_cents

      amount_cents = (prorated_min_amount_cents - used_amount_cents).round
      precise_amount_cents = prorated_min_amount_cents - used_precise_amount_cents
      unit_amount_cents = amount_cents
      precise_unit_amount = precise_amount_cents / charge.plan.amount.currency.subunit_to_unit.to_d

      true_up_fee = fee.dup
      true_up_fee.assign_attributes(
        amount_cents:,
        precise_amount_cents:,
        units: 1,
        total_aggregated_units: 1,
        events_count: 0,
        charge_filter_id: nil,
        true_up_parent_fee: fee,
        unit_amount_cents:,
        precise_unit_amount:
      )

      result.true_up_fee = true_up_fee
      result
    end

    private

    attr_reader :fee, :used_amount_cents, :used_precise_amount_cents, :boundaries

    delegate :charge, :subscription, to: :fee

    def prorated_min_amount_cents
      # NOTE: number of days between beginning of the period and the termination date
      from_datetime = boundaries.charges_from_datetime.to_time
      to_datetime = boundaries.charges_to_datetime.to_time
      number_of_day_to_bill = subscription.date_diff_with_timezone(from_datetime, to_datetime)

      date_service.charge_single_day_price(charge:) * number_of_day_to_bill
    end

    def date_service
      boundaries.timestamp = Time.zone.at(boundaries.timestamp) if boundaries.timestamp.is_a?(Integer)

      @date_service ||= Subscriptions::DatesService.new_instance(
        subscription,
        boundaries.timestamp ? Time.zone.parse(boundaries.timestamp) : Time.current,
        current_usage: subscription.terminated? && subscription.upgraded?
      )
    end
  end
end
