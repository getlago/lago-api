# frozen_string_literal: true

module Fees
  class ApplyTaxesService < BaseService
    def initialize(fee:)
      @fee = fee

      super
    end

    def call
      result.applied_taxes = []
      applied_taxes_amount_cents = 0
      applied_taxes_rate = 0

      applicable_taxes.each do |tax|
        applied_tax = Fee::AppliedTax.new(
          fee:,
          tax:,
          tax_description: tax.description,
          tax_code: tax.code,
          tax_name: tax.name,
          tax_rate: tax.rate,
          amount_currency: fee.amount_currency,
        )
        fee.applied_taxes << applied_tax

        tax_amount_cents = (fee.amount_cents * tax.rate).fdiv(100)
        applied_tax.amount_cents = tax_amount_cents.round
        applied_tax.save! if fee.persisted?

        applied_taxes_amount_cents += tax_amount_cents
        applied_taxes_rate += tax.rate

        result.applied_taxes << applied_tax
      end

      fee.taxes_amount_cents = applied_taxes_amount_cents.round
      fee.taxes_rate = applied_taxes_rate

      if fee.taxes_amount_cents.zero?
        # TODO(taxes): Remove the fallback on applicable vat to switch to new tax system
        fee.taxes_rate = customer.applicable_vat_rate
        fee.compute_vat
      end

      if fee.taxes_amount_cents.zero?
        # TODO(taxes): Remove the fallback on applicable vat to switch to new tax system
        fee.taxes_rate = customer.applicable_vat_rate
        fee.compute_vat
      end

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
