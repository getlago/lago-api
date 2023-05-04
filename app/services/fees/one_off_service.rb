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

          return result.not_found_failure!(resource: 'add_on') unless add_on

          unit_amount_cents = fee[:unit_amount_cents] || add_on.amount_cents
          units = fee[:units] || 1

          fee = Fee.new(
            invoice:,
            add_on:,
            description: fee[:description] || add_on.description,
            unit_amount_cents:,
            amount_cents: (unit_amount_cents * units).round,
            amount_currency: invoice.currency,
            vat_rate: customer.applicable_vat_rate,
            fee_type: :add_on,
            invoiceable_type: 'AddOn',
            invoiceable: add_on,
            units:,
            payment_status: :pending,
          )

          fee.compute_vat
          fee.save!

          fees_result << fee
        end
      end

      result.fees = fees_result
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
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
  end
end
