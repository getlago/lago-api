# frozen_string_literal: true

module Invoices
  class RefreshDraftService < BaseService
    def self.call(...)
      new(...).call
    end

    def initialize(invoice:)
      @invoice = invoice
      @subscription_ids = invoice.subscriptions.pluck(:id)
      super
    end

    def call
      result.invoice = invoice
      return result unless invoice.draft?

      ActiveRecord::Base.transaction do
        invoice.credit_notes.destroy_all
        invoice.credits.destroy_all
        invoice.wallet_transactions.destroy_all
        invoice.fees.destroy_all
        invoice.invoice_subscriptions.destroy_all

        invoice.update!(vat_rate: invoice.customer.applicable_vat_rate)

        calculate_result = Invoices::CalculateFeesService.call(
          invoice:,
          subscriptions: Subscription.find(subscription_ids),
          timestamp: invoice.created_at.to_i,
        )
        return calculate_result unless calculate_result.success?

        invoice.fees.update_all(created_at: invoice.created_at) # rubocop:disable Rails/SkipsModelValidations
      end

      result
    end

    private

    attr_accessor :invoice, :subscription_ids
  end
end
