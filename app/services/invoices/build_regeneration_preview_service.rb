# frozen_string_literal: true

module Invoices
  class BuildRegenerationPreviewService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:)
      @invoice = invoice

      super
    end

    def call
      preview_invoice = invoice.dup

      invoice.fees.includes(:adjusted_fee, charge: :billable_metric).find_each do |fee|
        dup_fee = fee.dup
        dup_fee.invoice = preview_invoice
        preview_invoice.fees << dup_fee

        refresh_charge_price(fee:, dup_fee:) if refreshable_charge_fee?(fee)

        result = Fees::ApplyTaxesService.call!(fee: dup_fee)
        result.raise_if_error!

        dup_fee.id = fee.id
        dup_fee.pricing_unit_usage&.fee_id = fee.id
        dup_fee.applied_taxes.each do |applied_tax|
          applied_tax.fee_id = fee.id
          applied_tax.id = SecureRandom.uuid
        end
      end

      # NOTE: Provider taxes doesn't apply in this service.
      # Since Lago calls external API to compute provider taxes, we want to avoid doing it and have a bad user experience
      # during the invoice regeneration preview.
      result = Invoices::ComputeAmountsFromFees.call(invoice: preview_invoice, provider_taxes: nil)
      result.raise_if_error!

      result.invoice.id = invoice.id
      result.invoice.applied_taxes.each do |applied_tax|
        applied_tax.invoice_id = invoice.id
        applied_tax.id = SecureRandom.uuid
      end

      result
    end

    private

    attr_reader :invoice

    def refresh_charge_price(fee:, dup_fee:)
      adjusted_fee = fee.adjusted_fee
      if adjusted_fee && !adjusted_fee.adjusted_display_name?
        adjusted_fee.charge ||= adjusted_fee.charge_with_discarded
        updated_fee = Fees::InitFromAdjustedChargeFeeService.call!(
          adjusted_fee:,
          boundaries: fee.properties,
          properties: fee.charge_filter&.properties || fee.charge.properties
        ).fee
        dup_fee.assign_attributes(updated_fee.attributes.slice(
          "units", "unit_amount_cents", "precise_unit_amount", "amount_cents",
          "precise_amount_cents", "amount_details", "invoice_display_name"
        ))
        dup_fee.pricing_unit_usage = updated_fee.pricing_unit_usage
      else
        dup_fee.invoice_display_name = adjusted_fee&.invoice_display_name || fee.invoice_display_name
        refresh_prorated_amount(fee:, dup_fee:)
      end
    end

    def refresh_prorated_amount(fee:, dup_fee:)
      metered_item = Fees::ChargeService::MeteredItem.from_charge(
        charge: fee.charge,
        charge_filter: fee.charge_filter,
        boundaries: BillingPeriodBoundaries.from_fee(fee)
      )
      metered_item = metered_item.with_default_filter unless fee.charge_filter
      matching = metered_item.matching_and_ignored_filters
      aggregation = BillableMetrics::AggregationFactory.new_instance(
        metered_item:,
        billing_context: Billing::Context.from(subscription: fee.subscription),
        boundaries: {
          from_datetime: Time.zone.parse(fee.properties.fetch("charges_from_datetime")),
          to_datetime: Time.zone.parse(fee.properties.fetch("charges_to_datetime")),
          charges_duration: fee.properties.fetch("charges_duration")
        },
        filters: {
          charge_id: fee.charge_id,
          charge_filter: fee.charge_filter,
          matching_filters: (matching.matching_filters || {}).merge(fee.grouped_by.transform_values { |value| [value] }),
          ignored_filters: matching.ignored_filters
        }
      ).aggregate(options: metered_item.aggregation_options(current_usage: false))
      aggregation.raise_if_error!

      # Fee units are unprorated; only the event aggregation carries the period weighting.
      aggregation.full_units_number = fee.units
      model_result = ChargeModels::Factory.new_instance(
        pricing_structure: ChargeModels::PricingStructure.from_charge(fee.charge).with(properties: metered_item.properties),
        aggregation_result: aggregation
      ).apply
      model_result.raise_if_error!
      amount = Fees::AmountsService.call!(
        currency: fee.amount.currency,
        charge_model_result: model_result,
        applied_pricing_unit: Fees::AmountsService::AppliedPricingUnit.from_applied_pricing_unit(fee.charge.applied_pricing_unit)
      ).amount
      dup_fee.assign_attributes(amount.to_h.except(:pricing_unit_usage))
      dup_fee.amount_details = model_result.amount_details
      dup_fee.pricing_unit_usage = amount.pricing_unit_usage
    end

    def refreshable_charge_fee?(fee)
      charge = fee.charge

      fee.charge? &&
        fee.true_up_parent_fee_id.nil? &&
        charge&.standard? &&
        charge.prorated? &&
        !charge.pay_in_advance? &&
        charge.billable_metric.sum_agg? &&
        charge.billable_metric.recurring?
    end
  end
end
