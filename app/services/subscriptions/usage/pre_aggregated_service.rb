# frozen_string_literal: true

module Subscriptions
  module Usage
    class PreAggregatedService < BaseService
      def initialize(subscription:, timestamp: Time.current)
        @subscription = subscription
        @timestamp = timestamp

        super
      end

      def call
        return result.not_found_failure!(resource: 'subscription') unless subscription
        return result.not_allowed_failure!(code: 'no_active_subscription') unless subscription.active?

        fetch_usage_units

        result.fees = []
        compute_usage

        result.amount_cents = result.fees.sum(&:amount_cents)
        result
      end

      private

      attr_reader :subscription, :timestamp
      attr_accessor :usage_units

      delegate :plan, to: :subscription

      def fetch_usage_units
        @usage_units = aggregation_types.each_with_object({}) do |aggregation_type, units|
          aggregator = Events::Stores::Clickhouse::PreAggregated::Factory.new_instance(
            aggregation_type:, subscription:, boundaries:
          )
          next units unless aggregator # TODO: Handle unsuported aggregation type

          agg_result = aggregator.call
          units.merge!(agg_result.charges_units)
          units
        end
      end

      def boundaries
        return @boundaries if @boundaries.present?

        date_service = Subscriptions::DatesService.new_instance(
          subscription,
          timestamp,
          current_usage: true
        )

        @boundaries = {
          from_datetime: date_service.from_datetime,
          to_datetime: date_service.to_datetime,
          charges_from_datetime: date_service.charges_from_datetime,
          charges_to_datetime: date_service.charges_to_datetime,
          issuing_date: date_service.next_end_of_period,
          charges_duration: date_service.charges_duration_in_days
        }
      end

      def charges
        @charges ||= plan.charges
          .includes(:billable_metric, filters: {values: :billable_metric_filter})
      end

      def aggregation_types
        charges.map { |c| c.billable_metric.aggregation_type }.uniq
      end

      def compute_usage
        charges.each do |charge|
          process_charge(charge, usage_units[charge.id] || {units: 0.0, grouped_by: {}})
          add_true_up_fee(charge)
        end
      end

      def process_charge(charge, charge_units)
        init_fees(charge, properties: charge.properties, units: charge_units) unless charge.filters.any?

        charge.filters.each do |charge_filter|
          filter_units = find_matching_filter_units(charge_filter, units[:filters])

          init_fees(charge, properties: charge_filter.properties, units: filter_units)
        end
      end

      def init_fees(charge, properties:, units:)
        if charge.standard? && properties['grouped_by'].present?
          filter_units[:grouped_by].each do |grouped_by, values|
            apply_charge_model(charge, values[:units], JSON.parse(grouped_by), properties)
          end
        else
          apply_charge_model(charge, units[:units], {}, properties)
        end
      end

      def find_matching_filter_units(charge_filter, filter_units)
        matching = filter_units.find do |k, _|
          f = JSON.parse(k)
          next unless charge_filter.to_h.keys.sort == f.keys.sort

          charge_filter.all? { |k, v| f[k].sort == v.sort }
        end

        matching || {units: 0.0, grouped_by: {}}
      end

      def apply_charge_model(charge, units, grouped_by, properties, charge_filter: nil)
        aggregation_result = BaseService::Result.new
        aggregation_result.grouped_by = grouped_by
        aggregation_result.count = 0
        aggregation_result.aggregation = units
        aggregation_result.current_usage_units = units

        charge_model_result = Charges::ChargeModelFactory.new_instance(charge:, aggregation_result:, properties:).apply

        rounded_amount = charge_model_result.amount.round(currency.exponent)
        amount_cents = rounded_amount * currency.subunit_to_unit
        unit_amount_cents = charge_model_result.unit_amount * currency.subunit_to_unit

        # TODO: Handle proration
        # units = if is_current_usage && charge.prorated?
        #   amount_result.current_usage_units
        # else
        #   amount_result.units
        # end

        result.fees << Fee.new(
          subscription:,
          charge:,
          amount_cents:,
          amount_currency: currency,
          fee_type: :charge,
          invoiceable: charge,
          units:,
          total_aggregated_units: units, # TODO: total_aggregated_units - proration ??
          properties: boundaries.to_h,
          events_count: 0, # TODO: Add support for event_count ??
          payment_status: :pending,
          taxes_amount_cents: 0,
          unit_amount_cents:,
          precise_unit_amount: charge_model_result.unit_amount,
          amount_details: charge_model_result.amount_details,
          grouped_by: charge_model_result.grouped_by || {},
          charge_filter_id: charge_filter&.id
        )
      end

      def add_true_up_fee(charge)
        charge_fees = result.fees.select { |f| f.charge == charge }
        true_up_fee = Fees::CreateTrueUpService.call(fee: charge_fees.first, amount_cents: charge_fees.sum(&:amount_cents)).true_up_fee
        result.fees << true_up_fee if true_up_fee
      end

      def currency
        @currency ||= plan.amount.currency
      end
    end
  end
end
