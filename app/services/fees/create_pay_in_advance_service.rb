# frozen_string_literal: true

module Fees
  class CreatePayInAdvanceService < BaseService
    Result = BaseResult[:fees, :invoice_id]

    def initialize(metered_item:, billing_at: nil, estimate: false)
      @metered_item = metered_item
      @billing_at = billing_at || metered_item.event.timestamp

      @estimate = estimate
      raise ArgumentError, "estimate must be true if event if not persisted" if !metered_item.event.persisted && !estimate

      super
    end

    def call
      return skip_missing_billing_context if billing_context.nil?

      fees = []

      ActiveRecord::Base.transaction(**isolation_mode) do
        metered_item.pricing_buckets.each do |selected_metered_item|
          fees << init_fee(selected_metered_item:)

          return result unless result.success?
        end
      end

      ActiveRecord::Base.transaction do
        result.fees = persist_fees(fees.compact)

        if !metered_item.invoiceable? && customer_provider_taxation?
          Fees::ApplyProviderTaxesToStandaloneFeesService.call!(
            customer: billing_context.customer, fees: result.fees, currency: metered_item.currency
          )
        end
      end

      deliver_webhooks

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def skip_missing_billing_context
      # NOTE: `event.subscription` is nil when the subscription was terminated before the
      # event's timestamp (e.g. enqueued while active, terminated before the job ran).
      message = "Fees::CreatePayInAdvanceService skipped: no active subscription for event"
      context = {
        organization_id: event.organization_id,
        external_subscription_id: event.external_subscription_id,
        event_transaction_id: event.transaction_id,
        event_timestamp: billing_at.iso8601
      }.merge(
        if metered_item.billing_segment
          {billing_segment_id: metered_item.billing_segment.id}
        else
          {charge_id: charge.id}
        end
      )

      Rails.logger.warn("#{message} #{context.map { |k, v| "#{k}=#{v}" }.join(" ")}")

      result.fees = []
      result
    end

    attr_reader :metered_item, :billing_at, :estimate

    delegate :charge, :event, :billable_metric, to: :metered_item

    def init_fee(selected_metered_item:)
      properties = selected_metered_item.properties
      charge_filter = selected_metered_item.charge_filter
      aggregation_result = aggregate(selected_metered_item:, properties:, charge_filter:)
      cache_aggregation_result(selected_metered_item:, aggregation_result:, charge_filter:)

      charge_model_result = apply_charge_model(selected_metered_item:, aggregation_result:, properties:)

      amount = Fees::AmountsService.call(
        currency: selected_metered_item.currency,
        charge_model_result:,
        applied_pricing_unit: Fees::AmountsService::AppliedPricingUnit.from_applied_pricing_unit(selected_metered_item.applied_pricing_unit)
      ).amount

      fee = Fee.new(
        organization_id: billing_context.organization_id,
        billing_entity_id: billing_context.applicable_billing_entity_id,
        subscription: billing_context.subscription,
        charge: selected_metered_item.billing_segment ? nil : selected_metered_item.charge,
        amount_cents: amount.amount_cents,
        precise_amount_cents: amount.precise_amount_cents,
        amount_currency: selected_metered_item.currency,
        fee_type: selected_metered_item.fee_type,
        invoiceable: selected_metered_item.invoiceable,
        rate_card_rate: selected_metered_item.rate_card_rate,
        rate_override: selected_metered_item.rate_override,
        product_filter: selected_metered_item.product_filter,
        units: charge_model_result.units,
        total_aggregated_units: charge_model_result.units,
        properties: selected_metered_item.billing_segment ? {} : selected_metered_item.filtered_for_charge_boundaries,
        events_count: charge_model_result.count,
        charge_filter: charge_filter&.persisted? ? charge_filter : nil,
        pay_in_advance_event_id: selected_metered_item.event.id,
        pay_in_advance_event_transaction_id: selected_metered_item.event.transaction_id,
        payment_status: :pending,
        pay_in_advance: true,
        taxes_amount_cents: 0,
        taxes_precise_amount_cents: 0.to_d,
        unit_amount_cents: amount.unit_amount_cents,
        precise_unit_amount: amount.precise_unit_amount,
        grouped_by: format_grouped_by(selected_metered_item:),
        amount_details: charge_model_result.amount_details || {},
        pricing_unit_usage: amount.pricing_unit_usage
      )

      build_breakdowns_for_fee(
        fee:,
        selected_metered_item:,
        presentation_breakdowns: remove_formated_grouped_by_keys(
          aggregation_result.pay_in_advance_breakdowns,
          selected_metered_item:
        )
      )

      fee
    end

    def persist_fees(fees)
      fees.map do |fee|
        # Non-invoiceable fees are regrouped later by AdvanceChargesService which
        # aggregates pre-existing fee taxes. They must have taxes applied now because
        # there is no ComputeTaxesAndTotalsService step for them.
        # Provider-taxed customers get taxes via apply_provider_taxes after persist.
        # Invoiceable fees get taxes applied later via ComputeTaxesAndTotalsService.
        if !metered_item.invoiceable? && !customer_provider_taxation?
          Fees::ApplyTaxesService.call!(fee:, customer: billing_context.customer)
        end

        fee.save! unless estimate
        fee
      end
    end

    def aggregate(selected_metered_item:, properties:, charge_filter: nil)
      Charges::PayInAdvanceAggregationService.call!(metered_item: selected_metered_item)
    end

    def apply_charge_model(selected_metered_item:, aggregation_result:, properties:)
      Charges::ApplyPayInAdvanceChargeModelService.call!(
        charge: selected_metered_item.charge, aggregation_result:, properties:
      )
    end

    def deliver_webhooks
      return if estimate

      result.fees.each { |f| SendWebhookJob.perform_later("fee.created", f) }
    end

    def build_breakdowns_for_fee(fee:, selected_metered_item:, presentation_breakdowns:)
      presentation_breakdowns.each do |breakdown|
        fee.presentation_breakdowns.build(
          presentation_by: breakdown[:groups],
          units: breakdown[:value],
          organization_id: selected_metered_item.organization_id
        )
      end
    end

    def cache_aggregation_result(selected_metered_item:, aggregation_result:, charge_filter:)
      return unless aggregation_result.current_aggregation.present? ||
        aggregation_result.max_aggregation.present? ||
        aggregation_result.max_aggregation_with_proration.present?

      CachedAggregation.create!(
        organization_id: event.organization_id,
        event_transaction_id: event.transaction_id,
        timestamp: billing_at,
        external_subscription_id: event.external_subscription_id,
        charge_id: selected_metered_item.charge_id,
        charge_filter_id: charge_filter&.id,
        current_aggregation: aggregation_result.current_aggregation,
        current_amount: aggregation_result.current_amount,
        max_aggregation: aggregation_result.max_aggregation,
        max_aggregation_with_proration: aggregation_result.max_aggregation_with_proration,
        grouped_by: format_grouped_by(selected_metered_item:),
        presentation_breakdowns: remove_formated_grouped_by_keys(
          aggregation_result.breakdowns,
          selected_metered_item:
        )
      )
    end

    def remove_formated_grouped_by_keys(breakdowns, selected_metered_item:)
      Array(breakdowns).map do |breakdown|
        breakdown.merge(groups: breakdown[:groups].except(*format_grouped_by(selected_metered_item:).keys))
      end
    end

    def format_grouped_by(selected_metered_item:)
      grouped_by = selected_metered_item.properties["pricing_group_keys"].presence || selected_metered_item.properties["grouped_by"] || []
      grouped_by << "target_wallet_code" if selected_metered_item.charge&.accepts_target_wallet && selected_metered_item.event.properties["target_wallet_code"].present?
      return {} if grouped_by.blank?

      grouped_by.index_with { |key| selected_metered_item.event.properties[key] }
    end

    def billing_context
      return @billing_context if defined?(@billing_context)

      @billing_context = if metered_item.billing_segment
        Billing::Context.from(contract: metered_item.contract)
      elsif event.subscription
        Billing::Context.from(subscription: event.subscription)
      end
    end

    def customer_provider_taxation?
      return @customer_provider_taxation if defined?(@customer_provider_taxation)

      @customer_provider_taxation = billing_context.customer.tax_customer.present?
    end

    def isolation_mode
      # NOTE: this is only to avoid failure with spec scnearios
      return {} if ActiveRecord::Base.connection.transaction_open?

      {isolation: :repeatable_read}
    end
  end
end
