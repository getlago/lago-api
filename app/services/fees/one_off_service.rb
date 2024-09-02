# frozen_string_literal: true

module Fees
  class OneOffService < BaseService
    def initialize(invoice:, fees:)
      @invoice = invoice
      @fees = fees

      super(nil)
    end

    def create
      fees_result = []

      ActiveRecord::Base.transaction do
        fees.each do |fee|
          add_on = add_on(identifier: fee[add_on_identifier])

          result.not_found_failure!(resource: 'add_on').raise_if_error! unless add_on

          unit_amount_cents = fee[:unit_amount_cents] || add_on.amount_cents
          units = fee[:units]&.to_f || 1
          tax_codes = fee[:tax_codes]

          fee = Fee.new(
            invoice:,
            add_on:,
            invoice_display_name: fee[:invoice_display_name].presence,
            description: fee[:description] || add_on.description,
            unit_amount_cents:,
            amount_cents: (unit_amount_cents * units).round,
            precise_amount_cents: unit_amount_cents * units,
            amount_currency: invoice.currency,
            fee_type: :add_on,
            invoiceable_type: 'AddOn',
            invoiceable: add_on,
            units:,
            payment_status: :pending,
            taxes_amount_cents: 0,
            taxes_precise_amount_cents: 0.0
          )
          fee.precise_unit_amount = fee.unit_amount.to_f

          unless customer_provider_taxation?
            taxes_result = if tax_codes
              Fees::ApplyTaxesService.call(fee:, tax_codes:)
            else
              Fees::ApplyTaxesService.call(fee:)
            end

            taxes_result.raise_if_error!
          end

          fee.save!

          fees_result << fee
        end

        if customer_provider_taxation?
          fee_taxes_result = apply_provider_taxes(fees_result)

          unless fee_taxes_result.success?
            return result.service_failure!(code: 'tax_error', message: fee_taxes_result.error.code)
          end
        end
      end

      result.fees = fees_result
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :invoice, :fees

    delegate :customer, to: :invoice

    def add_on(identifier:)
      finder = api_context? ? :code : :id

      invoice.organization.add_ons.find_by(finder => identifier)
    end

    def add_on_identifier
      api_context? ? :add_on_code : :add_on_id
    end

    def customer_provider_taxation?
      @apply_provider_taxes ||= customer.anrok_customer
    end

    def apply_provider_taxes(fees_result)
      taxes_result = Integrations::Aggregator::Taxes::Invoices::CreateService.call(invoice:, fees: fees_result)

      unless taxes_result.success?
        create_error_detail(taxes_result.error.code)

        return taxes_result
      end

      result.fees_taxes = taxes_result.fees

      fees_result.each do |fee|
        fee_taxes = result.fees_taxes.find { |item| item.item_id == fee.item_id }

        res = Fees::ApplyProviderTaxesService.call(fee:, fee_taxes:)
        res.raise_if_error!
      end

      taxes_result
    end

    def create_error_detail(code)
      error_result = ErrorDetails::CreateService.call(
        owner: invoice,
        organization: invoice.organization,
        params: {
          error_code: :tax_error,
          details: {
            tax_error: code
          }
        }
      )
      error_result.raise_if_error!
    end
  end
end
