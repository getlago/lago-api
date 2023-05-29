# frozen_string_literal: true

module Fees
  class ApplyTaxesService < BaseService
    def initialize(fee:)
      @fee = fee

      super
    end

    def call
      result.fees_taxes = []
      fee_taxes_amount_cents = 0
      fee_taxes_rate = 0

      applicable_taxes.each do |tax|
        fees_tax = FeesTax.new(
          fee:,
          tax:,
          tax_description: tax.description,
          tax_code: tax.code,
          tax_name: tax.name,
          tax_rate: tax.rate,
          amount_currency: fee.amount_currency,
        )
        fee.fees_taxes << fees_tax

        tax_amount_cents = (fee.amount_cents * tax.rate).fdiv(100)
        fees_tax.amount_cents = tax_amount_cents.round
        fees_tax.save! if fee.persisted?

        fee_taxes_amount_cents += tax_amount_cents
        fee_taxes_rate += tax.rate

        result.fees_taxes << fees_tax
      end

      fee.taxes_amount_cents = fee_taxes_amount_cents.round
      fee.taxes_rate = fee_taxes_rate

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :fee

    def customer
      @customer ||= fee.invoice&.customer || fee.subscription.customer
    end

    def applicable_taxes
      customer_taxes = customer.taxes
      return customer_taxes if customer_taxes.any?

      customer.organization.taxes.applied_to_organization
    end
  end
end
