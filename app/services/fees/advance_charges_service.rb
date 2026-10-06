# frozen_string_literal: true

module Fees
  class AdvanceChargesService < BaseService
    Result = BaseResult

    def initialize(invoice:, billing_contexts:, billing_at:, charge_fees_resolver: nil)
      @invoice = invoice
      @billing_contexts = billing_contexts
      @billing_at = billing_at
      @charge_fees_resolver = charge_fees_resolver

      super
    end

    def call
      attach_charge_fees
      result
    end

    private

    attr_reader :invoice, :billing_contexts, :billing_at, :charge_fees_resolver

    def attach_charge_fees
      return unless RegroupingChargeService.call!(billing_contexts:).regrouping_charge

      charge_fees.find_each do |fee|
        fee.update_column(:invoice_id, invoice.id) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def charge_fees
      resolver = charge_fees_resolver || AdvanceChargesToDatetimeFilterResolver.new(billing_contexts:, billing_at:)

      resolver.call.where(subscription_id: billing_contexts.map(&:subscription_id))
    end
  end
end
