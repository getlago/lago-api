# frozen_string_literal: true

module Invoices
  class ApplyProviderTaxesService < BaseService
    Result = BaseResult[:applied_taxes, :invoice]

    def initialize(invoice:, provider_taxes: nil)
      @invoice = invoice
      @provider_taxes = provider_taxes || fetch_provider_taxes_result.fees

      super
    end

    def call
      result.applied_taxes = []
      applied_taxes_amount_cents = 0
      taxes_rate = 0

      applicable_taxes.each do |key, tax|
        fee_taxes = indexed_fee_taxes.fetch(key)
        fees = fee_taxes.map(&:first)
        tax_rate = tax.rate.to_f * 100

        applied_tax = invoice.applied_taxes.new(
          organization: invoice.organization,
          tax_description: tax.type,
          tax_code: tax.name.parameterize(separator: "_"),
          tax_name: tax.name,
          tax_rate: tax_rate,
          amount_currency: invoice.currency
        )
        invoice.applied_taxes << applied_tax

        # Preserve the cents already allocated to fees by the provider calculation.
        tax_amount_cents = fee_taxes.sum { |_fee, fee_tax| fee_tax.amount_cents }
        applied_tax.fees_amount_cents = fees_amount_cents(fees)
        applied_tax.taxable_base_amount_cents = taxable_base_amount_cents(fees).round
        applied_tax.amount_cents = tax_amount_cents.round

        # NOTE: when applied on user current usage, the invoice is
        #       not created in DB
        applied_tax.save! if invoice.persisted?

        applied_taxes_amount_cents += tax_amount_cents
        taxes_rate += pro_rated_taxes_rate(tax, fees)

        result.applied_taxes << applied_tax
      end

      invoice.taxes_amount_cents = applied_taxes_amount_cents.round
      invoice.taxes_rate = taxes_rate.round(5)
      result.invoice = invoice

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice, :provider_taxes

    def applicable_taxes
      @applicable_taxes ||= provider_taxes.flat_map(&:tax_breakdown).each_with_object({}) do |tax, output|
        key = tax_key(name: tax.name, rate: tax.rate, type: tax.type)
        output[key] ||= tax
      end
    end

    def indexed_fee_taxes
      @indexed_fee_taxes ||= invoice.fees.each_with_object({}) do |fee, output|
        fee.applied_taxes.each do |applied_tax|
          key = tax_key(
            name: applied_tax.tax_name,
            rate: applied_tax.tax_rate,
            type: applied_tax.tax_description
          )
          output[key] ||= []
          output[key] << [fee, applied_tax]
        end
      end
    end

    def pro_rated_taxes_rate(tax, fees)
      tax_rate = tax.rate.is_a?(String) ? tax.rate.to_f * 100 : tax.rate

      fees_rate = if invoice.sub_total_excluding_taxes_amount_cents.positive?
        fees_amount_cents(fees).fdiv(invoice.sub_total_excluding_taxes_amount_cents)
      else
        # NOTE: when invoice have a 0 amount. The prorata is on the number of fees.
        #       Fees with no taxable base are not reported and carry no tax row, so they are
        #       out of the denominator too; counting them would dilute the rate below the one
        #       the provider returned.
        fees.count.fdiv(taxed_fees_count)
      end

      fees_rate * tax_rate
    end

    def taxed_fees_count
      indexed_fee_taxes.values.flat_map { |entries| entries.map(&:first) }.uniq.count
    end

    def fees_amount_cents(fees)
      fees.sum(&:sub_total_excluding_taxes_amount_cents)
    end

    def taxable_base_amount_cents(fees)
      fees.sum { |fee| fee.sub_total_excluding_taxes_amount_cents * fee.taxes_base_rate }
    end

    def fetch_provider_taxes_result
      taxes_result = if invoice.draft? || invoice.advance_charges?
        Integrations::Aggregator::Taxes::Invoices::CreateDraftService.call(invoice:)
      else
        Integrations::Aggregator::Taxes::Invoices::CreateService.call(invoice:)
      end
      taxes_result.raise_if_error!
    end

    def tax_key(name:, rate:, type:)
      tax_rate = rate.is_a?(String) ? rate.to_f * 100 : rate

      "#{type}-#{name.parameterize(separator: "_")}-#{tax_rate}"
    end
  end
end
