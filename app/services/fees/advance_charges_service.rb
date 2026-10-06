# frozen_string_literal: true

module Fees
  class AdvanceChargesService < BaseService
    Result = BaseResult

    def initialize(invoice:, billing_contexts:, billing_at:)
      @invoice = invoice
      @billing_contexts = billing_contexts
      @billing_at = billing_at

      super
    end

    def call
      attach_charge_fees
      result
    end

    private

    attr_reader :invoice, :billing_contexts, :billing_at

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
  end
end
