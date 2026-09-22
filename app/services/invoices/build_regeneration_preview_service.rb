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
      properties = fee.charge_filter&.properties || fee.charge.properties
      result = Fees::InitFromAdjustedChargeFeeService.call!(
        adjusted_fee: adjusted_fee_for(fee),
        boundaries: fee.properties,
        properties:
      )

      updated_fee = result.fee
      dup_fee.assign_attributes(
        updated_fee.attributes.slice(
          "invoice_display_name",
          "charge_id",
          "subscription_id",
          "units",
          "unit_amount_cents",
          "precise_unit_amount",
          "amount_cents",
          "precise_amount_cents",
          "amount_details",
          "charge_filter"
        )
      )
      dup_fee.pricing_unit_usage = updated_fee.pricing_unit_usage
    end

    def refreshable_charge_fee?(fee)
      charge = fee.charge

      fee.charge? &&
        fee.true_up_parent_fee_id.nil? &&
        charge&.standard? &&
        charge.prorated? &&
        charge.billable_metric.sum_agg? &&
        charge.billable_metric.recurring?
    end

    def adjusted_fee_for(fee)
      adjusted_fee = fee.adjusted_fee
      if adjusted_fee && !adjusted_fee.adjusted_display_name?
        adjusted_fee.charge ||= adjusted_fee.charge_with_discarded
        return adjusted_fee
      end

      AdjustedFee.new(
        fee:,
        invoice: fee.invoice,
        subscription: fee.subscription,
        charge: fee.charge,
        adjusted_units: true,
        adjusted_amount: false,
        invoice_display_name: adjusted_fee&.invoice_display_name || fee.invoice_display_name,
        fee_type: fee.fee_type,
        properties: fee.properties,
        units: fee.units,
        grouped_by: fee.grouped_by,
        charge_filter: fee.charge_filter,
        organization: fee.organization
      )
    end
  end
end
