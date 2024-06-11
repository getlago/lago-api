# frozen_string_literal: true

module Fees
  class ChargeService < BaseService
    def initialize(invoice:, charge:, subscription:, boundaries:, currency: nil)
      @invoice = invoice
      @charge = charge
      @subscription = subscription
      @is_current_usage = false
      @boundaries = OpenStruct.new(boundaries)
      @currency = currency || invoice.total_amount.currency

      super(nil)
    end

    def create
      return result if already_billed?

      init_fees
      init_true_up_fee(fee: result.fees.first, amount_cents: result.fees.sum(&:amount_cents))
      return result unless result.success?

      ActiveRecord::Base.transaction do
        result.fees.each do |fee|
          fee.save!

          next unless invoice&.draft? && fee.true_up_parent_fee.nil? && adjusted_fee(
            charge_filter: fee.charge_filter,
            grouped_by: fee.grouped_by
          )

          adjusted_fee(charge_filter: fee.charge_filter, grouped_by: fee.grouped_by).update!(fee:)
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def current_usage
      @is_current_usage = true

      init_fees
      result
    end

    private

    attr_accessor :invoice, :charge, :subscription, :boundaries, :is_current_usage, :currency

    # delegate :customer, to: :invoice
    delegate :billable_metric, to: :charge
    delegate :plan, to: :subscription

    def init_fees
      result.fees = []

      return init_charge_fees(properties: charge.properties) unless charge.filters.any?

      # NOTE: Create a fee for each filters defined on the charge.
      charge.filters.each do |charge_filter|
        init_charge_fees(properties: charge_filter.properties, charge_filter:)
      end

      # NOTE: Create a fee for events not matching any filters.
      init_charge_fees(properties: charge.properties, charge_filter: ChargeFilter.new(charge:))
    end

    def init_charge_fees(properties:, charge_filter: nil)
      charge_model_result = apply_aggregation_and_charge_model(properties:, charge_filter:)
      return result.fail_with_error!(charge_model_result.error) unless charge_model_result.success?

      (charge_model_result.grouped_results || [charge_model_result]).each do |amount_result|
        init_fee(amount_result, properties:, charge_filter:)
      end
    end

    def init_fee(amount_result, properties:, charge_filter:)
      # NOTE: Build fee for case when there is adjusted fee and units or amount has been adjusted.
      # Base fee creation flow handles case when only name has been adjusted
      if invoice&.draft? && (adjusted = adjusted_fee(
        charge_filter:,
        grouped_by: amount_result.grouped_by
      )) && !adjusted.adjusted_display_name?
        adjustement_result = Fees::InitFromAdjustedChargeFeeService.call(
          adjusted_fee: adjusted,
          boundaries:,
          properties:
        )
        return result.fail_with_error!(adjustement_result.error) unless adjustement_result.success?

        result.fees << adjustement_result.fee
        return
      end

      # NOTE: amount_result should be a BigDecimal, we need to round it
      # to the currency decimals and transform it into currency cents
      rounded_amount = amount_result.amount.round(currency.exponent)
      amount_cents = rounded_amount * currency.subunit_to_unit
      unit_amount_cents = amount_result.unit_amount * currency.subunit_to_unit

      units = if is_current_usage && (charge.pay_in_advance? || charge.prorated?)
        amount_result.current_usage_units
      elsif charge.prorated?
        amount_result.full_units_number.nil? ? amount_result.units : amount_result.full_units_number
      else
        amount_result.units
      end

      new_fee = Fee.new(
        invoice:,
        subscription:,
        charge:,
        amount_cents:,
        amount_currency: currency,
        fee_type: :charge,
        invoiceable_type: 'Charge',
        invoiceable: charge,
        units:,
        total_aggregated_units: amount_result.total_aggregated_units || units,
        properties: boundaries.to_h,
        events_count: amount_result.count,
        payment_status: :pending,
        taxes_amount_cents: 0,
        unit_amount_cents:,
        precise_unit_amount: amount_result.unit_amount,
        amount_details: amount_result.amount_details,
        grouped_by: amount_result.grouped_by || {},
        charge_filter_id: charge_filter&.id
      )

      if (adjusted = adjusted_fee(charge_filter:, grouped_by: amount_result.grouped_by))&.adjusted_display_name?
        new_fee.invoice_display_name = adjusted.invoice_display_name
      end

      result.fees << new_fee
    end

    def adjusted_fee(charge_filter:, grouped_by:)
      @adjusted_fee ||= {}

      key = [
        charge_filter&.id,
        (grouped_by || {}).map do |k, v|
          "#{k}-#{v}"
        end.sort.join('|')
      ].compact.join('|')
      key = 'default' if key.blank?

      return @adjusted_fee[key] if @adjusted_fee.key?(key)

      scope = AdjustedFee
        .where(invoice:, subscription:, charge:, charge_filter:, fee_type: :charge)
        .where("(properties->>'charges_from_datetime')::timestamptz = ?", boundaries.charges_from_datetime&.iso8601(3))
        .where("(properties->>'charges_to_datetime')::timestamptz = ?", boundaries.charges_to_datetime&.iso8601(3))

      scope = if grouped_by.present?
        scope.where(grouped_by:)
      else
        scope.where(grouped_by: {})
      end

      @adjusted_fee[key] = scope.first
    end

    def init_true_up_fee(fee:, amount_cents:)
      true_up_fee = Fees::CreateTrueUpService.call(fee:, amount_cents:).true_up_fee
      result.fees << true_up_fee if true_up_fee
    end

    def apply_aggregation_and_charge_model(properties:, charge_filter: nil)
      aggregation_result = aggregator(charge_filter:).aggregate(options: options(properties))
      return aggregation_result unless aggregation_result.success?

      if billable_metric.recurring?
        persist_recurring_value(aggregation_result.aggregations || [aggregation_result], charge_filter)
      end

      Charges::ChargeModelFactory.new_instance(charge:, aggregation_result:, properties:).apply
    end

    def options(properties)
      {
        free_units_per_events: properties['free_units_per_events'].to_i,
        free_units_per_total_aggregation: BigDecimal(properties['free_units_per_total_aggregation'] || 0),
        is_current_usage:,
        is_pay_in_advance: charge.pay_in_advance?
      }
    end

    def already_billed?
      existing_fees = if invoice
        invoice.fees.where(charge_id: charge.id, subscription_id: subscription.id)
      else
        Fee.where(charge_id: charge.id, subscription_id: subscription.id, invoice_id: nil, pay_in_advance_event_id: nil)
      end

      return false if existing_fees.blank?

      result.fees = existing_fees
      true
    end

    def aggregator(charge_filter:)
      BillableMetrics::AggregationFactory.new_instance(
        charge:,
        current_usage: is_current_usage,
        subscription:,
        boundaries: {
          from_datetime: boundaries.charges_from_datetime,
          to_datetime: boundaries.charges_to_datetime,
          charges_duration: boundaries.charges_duration
        },
        filters: aggregation_filters(charge_filter:)
      )
    end

    def persist_recurring_value(aggregation_results, charge_filter)
      return if is_current_usage

      # NOTE: Only weighted sum and custom aggregations are setting this value
      return unless aggregation_results.first&.recurring_updated_at

      result.cached_aggregations ||= []

      # NOTE: persist current recurring value for next period
      aggregation_results.each do |aggregation_result|
        result.cached_aggregations << CachedAggregation.find_or_initialize_by(
          organization_id: billable_metric.organization_id,
          external_subscription_id: subscription.external_id,
          charge_id: charge.id,
          charge_filter_id: charge_filter&.id,
          grouped_by: aggregation_result.grouped_by || {},
          timestamp: aggregation_result.recurring_updated_at
        ) do |aggregation|
          aggregation.current_aggregation = aggregation_result.total_aggregated_units || aggregation_result.aggregation
          aggregation.current_amount = aggregation_result.custom_aggregation&.[](:amount)
          aggregation.save!
        end
      end
    end

    def aggregation_filters(charge_filter: nil)
      filters = {}

      properties = charge_filter&.properties || charge.properties
      filters[:grouped_by] = properties['grouped_by'] if charge.standard? && properties['grouped_by'].present?

      if charge_filter.present?
        result = ChargeFilters::MatchingAndIgnoredService.call(charge:, filter: charge_filter)
        filters[:charge_filter] = charge_filter
        filters[:matching_filters] = result.matching_filters
        filters[:ignored_filters] = result.ignored_filters
      end

      filters
    end
  end
end
