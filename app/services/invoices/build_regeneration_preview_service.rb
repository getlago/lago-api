# frozen_string_literal: true

module Invoices
  class BuildRegenerationPreviewService < BaseService
    Result = BaseResult[:invoice]

    REPRICED_ATTRIBUTES = %w[
      units
      total_aggregated_units
      events_count
      amount_cents
      precise_amount_cents
      unit_amount_cents
      precise_unit_amount
      amount_details
    ].freeze

    BOUNDARY_DATETIME_KEYS = %w[
      from_datetime
      to_datetime
      charges_from_datetime
      charges_to_datetime
      timestamp
      fixed_charges_from_datetime
      fixed_charges_to_datetime
    ].freeze

    def initialize(invoice:)
      @invoice = invoice

      super
    end

    def call
      preview_invoice = invoice.dup

      invoice.fees.each do |fee|
        dup_fee = fee.dup
        dup_fee.invoice = preview_invoice
        reprice(dup_fee, repriced_fees[fee.id])
        preview_invoice.fees << dup_fee

        result = Fees::ApplyTaxesService.call!(fee: dup_fee)
        result.raise_if_error!

        dup_fee.id = fee.id
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

    def reprice(dup_fee, repriced_fee)
      return unless repriced_fee

      dup_fee.assign_attributes(repriced_fee.attributes.slice(*REPRICED_ATTRIBUTES))

      if repriced_fee.pricing_unit_usage
        dup_fee.pricing_unit_usage = repriced_fee.pricing_unit_usage.dup
      end
    end

    # NOTE: Eligible charge fees are priced again as billing would price them today for the same
    #       period: current events and the current price of the charge. Fees without a match keep
    #       their historical values. Returns a Hash of voided fee id => unsaved repriced fee.
    def repriced_fees
      @repriced_fees ||= begin
        current_charges = invoice.fees.each_with_object({}) do |fee, charges|
          next unless repriceable?(fee)

          current = Fees::ResolveCurrentChargeService.call!(
            subscription: fee.subscription,
            charge: fee.charge,
            charge_filter: fee.charge_filter
          )
          next unless current.charge

          charges[fee] = current
        end

        current_charges
          .group_by do |fee, current|
            [
              fee.subscription_id,
              current.charge.id,
              fee.properties["charges_from_datetime"],
              fee.properties["charges_to_datetime"]
            ]
          end
          .each_with_object({}) do |(_key, group), repriced|
            fees = price_with_current_charge(group.first.first, group.first.last.charge)

            group.each do |voided_fee, current|
              match = fees.find do |fee|
                fee.charge_filter_id == current.charge_filter&.id &&
                  (fee.grouped_by || {}).to_h.stringify_keys == (voided_fee.grouped_by || {}).to_h.stringify_keys
              end

              repriced[voided_fee.id] = match if match
            end
          end
      end
    end

    def repriceable?(fee)
      return false unless fee.charge?
      return false if fee.true_up_parent_fee_id.present?
      return false if fee.adjusted_fee.present?
      return false if fee.pay_in_advance_event_id.present? || fee.pay_in_advance
      return false if invoice.progressive_billing?

      fee.subscription.present?
    end

    def price_with_current_charge(fee, current_charge)
      boundaries = boundaries_from(fee)

      Fees::ChargeService
        .call!(
          # NOTE: A throwaway unsaved invoice: the persisted voided invoice would be seen as
          #       already billed, and the preview invoice must not collect these fees.
          invoice: invoice.dup,
          metered_item: Fees::ChargeService::MeteredItem.from_charge(charge: current_charge, boundaries:),
          billing_context: Billing::Context.from(subscription: fee.subscription),
          options: Fees::ChargeService::Options.new(context: :invoice_preview, skip_adjusted_fees: true)
        )
        .fees
        .select { |repriced_fee| repriced_fee.true_up_parent_fee.nil? }
    end

    def boundaries_from(fee)
      properties = fee.properties.to_h.stringify_keys
      datetimes = BOUNDARY_DATETIME_KEYS.index_with do |key|
        properties[key].presence && Time.zone.parse(properties[key].to_s)
      end

      BillingPeriodBoundaries.new(
        from_datetime: datetimes["from_datetime"],
        to_datetime: datetimes["to_datetime"],
        charges_from_datetime: datetimes["charges_from_datetime"],
        charges_to_datetime: datetimes["charges_to_datetime"],
        charges_duration: properties["charges_duration"],
        timestamp: datetimes["timestamp"],
        fixed_charges_from_datetime: datetimes["fixed_charges_from_datetime"],
        fixed_charges_to_datetime: datetimes["fixed_charges_to_datetime"],
        fixed_charges_duration: properties["fixed_charges_duration"]
      )
    end
  end
end
