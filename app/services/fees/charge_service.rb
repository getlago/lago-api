# frozen_string_literal: true

module Fees
  class ChargeService < BaseService
    def initialize(invoice:, charge:, subscription:, boundaries:)
      @invoice = invoice
      @charge = charge
      @subscription = subscription
      @is_current_usage = false
      @boundaries = OpenStruct.new(boundaries)
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

          if invoice.draft? && fee.true_up_parent_fee.nil? && adjusted_fee(fee.group)
            adjusted_fee(fee.group).update!(fee:)
          end
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

    attr_accessor :invoice, :charge, :subscription, :boundaries, :is_current_usage

    delegate :customer, to: :invoice
    delegate :billable_metric, to: :charge
    delegate :plan, to: :subscription

    def init_fees
      result.fees = []

      if billable_metric.selectable_groups.any?
        # NOTE: Create a fee for each groups defined on the charge.
        charge.group_properties.each do |group_properties|
          group = billable_metric.selectable_groups.find_by(id: group_properties.group_id)
          init_fee(properties: group_properties.values, group:)
        end

        # NOTE: Create a fee for groups not defined (with default properties).
        billable_metric.selectable_groups.where.not(id: charge.group_properties.pluck(:group_id)).each do |group|
          init_fee(properties: charge.properties, group:)
        end
      else
        init_fee(properties: charge.properties)
      end
    end

    def init_fee(properties:, group: nil)
      # NOTE: Build fee for case when there is adjusted fee and units or amount has been adjusted.
      # Base fee creation flow handles case when only name has been adjusted
      if invoice.draft? && (adjusted = adjusted_fee(group)) && !adjusted.adjusted_display_name?
        adjustement_result = Fees::InitFromAdjustedChargeFeeService.call(
          adjusted_fee: adjusted,
          boundaries:,
          properties:,
        )
        return result.fail_with_error!(adjustement_result.error) unless adjustement_result.success?

        result.fees << adjustement_result.fee
        return
      end

      amount_result = compute_amount(properties:, group:)
      return result.fail_with_error!(amount_result.error) unless amount_result.success?

      # NOTE: amount_result should be a BigDecimal, we need to round it
      # to the currency decimals and transform it into currency cents
      currency = invoice.total_amount.currency
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
        group_id: group&.id,
        payment_status: :pending,
        taxes_amount_cents: 0,
        unit_amount_cents:,
        precise_unit_amount: amount_result.unit_amount,
        amount_details: amount_result.amount_details,
      )

      if adjusted_fee(group)&.adjusted_display_name?
        new_fee.invoice_display_name = adjusted_fee(group).invoice_display_name
      end

      result.fees << new_fee
    end

    def adjusted_fee(group)
      @adjusted_fee ||= {}

      key = group ? group.id : 'default'

      return @adjusted_fee[key] if @adjusted_fee.key?(key)

      @adjusted_fee[key] = AdjustedFee
        .where(invoice:, subscription:, charge:, group:, fee_type: :charge)
        .where("properties->>'charges_from_datetime' = ?", boundaries.charges_from_datetime&.iso8601(3))
        .where("properties->>'charges_to_datetime' = ?", boundaries.charges_to_datetime&.iso8601(3))
        .first
    end

    def init_true_up_fee(fee:, amount_cents:)
      true_up_fee = Fees::CreateTrueUpService.call(fee:, amount_cents:).true_up_fee
      result.fees << true_up_fee if true_up_fee
    end

    def compute_amount(properties:, group: nil)
      aggregation_result = aggregator(group:).aggregate(options: options(properties))
      return aggregation_result unless aggregation_result.success?

      persist_recurring_value(aggregation_result, group) if billable_metric.recurring?
      apply_charge_model_service(aggregation_result, properties)
    end

    def options(properties)
      {
        free_units_per_events: properties['free_units_per_events'].to_i,
        free_units_per_total_aggregation: BigDecimal(properties['free_units_per_total_aggregation'] || 0),
        is_current_usage:,
        is_pay_in_advance: charge.pay_in_advance?,
      }
    end

    def already_billed?
      existing_fees = invoice.fees.where(charge_id: charge.id, subscription_id: subscription.id)
      return false if existing_fees.blank?

      result.fees = existing_fees
      true
    end

    def aggregator(group:)
      BillableMetrics::AggregationFactory.new_instance(
        charge:,
        current_usage: is_current_usage,
        subscription:,
        boundaries: {
          from_datetime: boundaries.charges_from_datetime,
          to_datetime: boundaries.charges_to_datetime,
          charges_duration: boundaries.charges_duration,
        },
        filters: { group: },
      )
    end

    def apply_charge_model_service(aggregation_result, properties)
      Charges::ChargeModelFactory.new_instance(charge:, aggregation_result:, properties:).apply
    end

    def persist_recurring_value(aggregation_result, group)
      return if is_current_usage

      # NOTE: Only weighted sum aggregation is setting this value
      return unless aggregation_result.recurring_updated_at

      result.quantified_events ||= []

      # NOTE: persist current recurring value for next period
      result.quantified_events << QuantifiedEvent.find_or_initialize_by(
        organization_id: billable_metric.organization_id,
        external_subscription_id: subscription.external_id,
        group_id: group&.id,
        billable_metric_id: billable_metric.id,
        added_at: aggregation_result.recurring_updated_at,
      ) do |event|
        event.properties[QuantifiedEvent::RECURRING_TOTAL_UNITS] = aggregation_result.total_aggregated_units
        event.save!
      end
    end
  end
end
