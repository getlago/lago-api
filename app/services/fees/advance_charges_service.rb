# frozen_string_literal: true

module Fees
  class AdvanceChargesService < BaseService
    Result = BaseResult[:invoiced_metered_items]

    def initialize(invoice:, billing_contexts:, billing_at:, metered_items: [])
      @invoice = invoice
      @billing_contexts = billing_contexts
      @billing_at = billing_at
      @metered_items = metered_items

      super
    end

    def call
      result.invoiced_metered_items = []

      if metered_items.empty?
        attach_charge_fees
      else
        attach_product_fees
      end

      result
    end

    private

    attr_reader :invoice, :billing_contexts, :billing_at, :metered_items

    def attach_charge_fees
      if RegroupingChargeService.call!(billing_contexts: invoice_billing_contexts).regrouping_charge
        charge_fees.update_all(invoice_id: invoice.id) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def charge_fees
      # Eligibility uses the original billing run; attachment is limited to this invoice's group.
      resolver = AdvanceChargesToDatetimeFilterResolver.new(billing_contexts:, billing_at:)

      resolver.call.where(subscription_id: invoice_billing_contexts.map(&:subscription_id))
    end

    def invoice_billing_contexts
      @invoice_billing_contexts ||= invoice.subscriptions.map { |subscription| Billing::Context.from(subscription:) }
    end

    def attach_product_fees
      regrouped_metered_items = metered_items.select(&:regroup_paid_fees_invoice?)
      return if regrouped_metered_items.empty?

      resolver = AdvanceChargesToDatetimeFilterResolver.new(billing_contexts:, billing_at:, metered_items: regrouped_metered_items)
      fees = resolver.call
      result.invoiced_metered_items = resolver.metered_items_with_fees(fees)

      fees.update_all(invoice_id: invoice.id) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
