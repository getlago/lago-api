# frozen_string_literal: true

module Fees
  class EstimateInstantPayInAdvanceService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      # NOTE: validation is shared with event creation and is expecting a transaction_id
      @event_params = params
      @billing_at = event.timestamp

      super
    end

    def call
      validation_result = Events::ValidateCreationService.call(organization:, event_params:, customer:, subscriptions:)
      return validation_result unless validation_result.success?

      if charges.none?
        return result.single_validation_failure!(field: :code, error_code: 'does_not_match_an_instant_charge')
      end

      fees = charges.map { |charge| estimate_charge_fees(charge) }

      result.fees = fees
      result
    end

    private

    attr_reader :event_params, :organization, :billing_at
    delegate :subscription, to: :event
    delegate :customer, to: :subscription, allow_nil: true

    def estimate_charge_fees(charge)
      charge_filter = ChargeFilters::EventMatchingService.call(charge:, event:).charge_filter
      properties = charge_filter&.properties || charge.properties

      # fetch value and apply rounding
      billable_metric = charge.billable_metric
      units = BigDecimal(event.properties[charge.billable_metric.field_name] || 0)
      units = BillableMetrics::Aggregations::ApplyRoundingService.call!(billable_metric:, units:).units

      estimate_result = Charges::EstimateInstant::PercentageService.call!(properties:, units:)

      amount = estimate_result.amount
      # NOTE: amount_result should be a BigDecimal, we need to round it
      # to the currency decimals and transform it into currency cents
      rounded_amount = amount.round(currency.exponent)
      amount_cents = rounded_amount * currency.subunit_to_unit
      unit_amount = rounded_amount.zero? ? BigDecimal("0") : rounded_amount / units
      unit_amount_cents = unit_amount * currency.subunit_to_unit

      # construct payload directly
      {
        lago_id: nil,
        lago_charge_id: charge.id,
        lago_charge_filter_id: charge_filter&.id,
        lago_invoice_id: nil,
        lago_true_up_fee_id: nil,
        lago_true_up_parent_fee_id: nil,
        lago_subscription_id: subscription.id,
        external_subscription_id: subscription.external_id,
        lago_customer_id: customer.id,
        external_customer_id: customer.external_id,
        item: {
          type: 'charge',
          code: billable_metric.code,
          name: billable_metric.name,
          description: billable_metric.description,
          invoice_display_name: charge.invoice_display_name.presence || billable_metric.name,
          filters: charge_filter&.to_h,
          filter_invoice_display_name: charge_filter&.display_name,
          lago_item_id: billable_metric.id,
          item_type: BillableMetric.name,
          grouped_by: {}
        },
        pay_in_advance: true,
        invoiceable: charge.invoiceable,
        amount_cents:,
        amount_currency: currency.iso_code,
        precise_amount: amount,
        precise_total_amount: amount,
        taxes_amount_cents: 0,
        taxes_precise_amount: 0,
        taxes_rate: 0,
        total_amount_cents: amount_cents,
        total_amount_currency: currency.iso_code,
        units: units,
        description: nil,
        precise_unit_amount: unit_amount_cents,
        precise_coupons_amount_cents: "0.0",
        events_count: 1,
        payment_status: "pending",
        created_at: nil,
        succeeded_at: nil,
        failed_at: nil,
        refunded_at: nil,
        amount_details: nil,
        from_date: boundaries[:charges_from_datetime]&.to_datetime&.iso8601,
        to_date: boundaries[:charges_to_datetime]&.to_datetime&.end_of_day&.iso8601,
        event_transaction_id: event.transaction_id
      }
    end

    def boundaries
      @boundaries ||= {
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        charges_duration: date_service.charges_duration_in_days,
        timestamp: billing_at
      }
    end

    def event
      return @event if @event

      @event = Event.new(
        organization_id: organization.id,
        code: event_params[:code],
        external_subscription_id: event_params[:external_subscription_id],
        properties: event_params[:properties] || {},
        transaction_id: event_params[:transaction_id] || SecureRandom.uuid,
        timestamp: Time.current
      )
    end

    def date_service
      @date_service ||= Subscriptions::DatesService.new_instance(
        subscription,
        billing_at,
        current_usage: true
      )
    end

    def subscriptions
      return @subscriptions if defined? @subscriptions

      subscriptions = organization.subscriptions.where(external_id: event.external_subscription_id)
      return unless subscriptions

      timestamp = event.timestamp
      @subscriptions = subscriptions
        .where("date_trunc('second', started_at::timestamp) <= ?", timestamp)
        .where("terminated_at IS NULL OR date_trunc('second', terminated_at::timestamp) >= ?", timestamp)
        .order('terminated_at DESC NULLS FIRST, started_at DESC')
    end

    def charges
      @charges ||= subscriptions.first
        .plan
        .charges
        .percentage
        .pay_in_advance
        .joins(:billable_metric)
        .where(billable_metric: {code: event.code})
    end

    def currency
      subscription.plan.amount.currency
    end
  end
end
