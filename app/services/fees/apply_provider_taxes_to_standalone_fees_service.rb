# frozen_string_literal: true

module Fees
  class ApplyProviderTaxesToStandaloneFeesService < BaseService
    Result = BaseResult

    def initialize(customer:, fees:, currency:)
      @customer = customer
      @fees = fees
      @currency = currency

      super
    end

    def call
      taxes_result = Integrations::Aggregator::Taxes::Invoices::CreateService.call(
        invoice: fake_invoice, fees:
      )
      return result unless taxes_result.success?

      fees.each do |fee|
        Fees::ApplyProviderTaxesService.call!(fee:, fee_taxes: fee_taxes(fee, taxes_result.fees))
      end

      Fees::ReconcileGroupedProviderTaxesService.call!(fees:, provider_taxes: taxes_result.fees)

      result
    end

    private

    attr_reader :customer, :fees, :currency

    FakeInvoice = Data.define(:id, :issuing_date, :currency, :customer, :billing_entity)

    # NOTE: Fees of a charge split by filters share one item_id when they are not persisted,
    #       since it falls back to the billable metric. item_key stays unique either way.
    def fee_taxes(fee, provider_taxes)
      provider_taxes.find { |item| item.item_key == fee.item_key } ||
        provider_taxes.find { |item| item.item_id == (fee.id || fee.item_id) }
    end

    def fake_invoice
      FakeInvoice.new(
        id: SecureRandom.uuid,
        issuing_date: Time.current.in_time_zone(customer.applicable_timezone).to_date,
        currency:,
        customer:,
        billing_entity: customer.billing_entity
      )
    end
  end
end
