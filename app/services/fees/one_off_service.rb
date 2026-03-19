# frozen_string_literal: true

module Fees
  class OneOffService < BaseService
    def initialize(invoice:, fees:)
      @invoice = invoice
      @fees = fees

      super(nil)
    end

    def call
      fees_result = []

      ActiveRecord::Base.transaction do
        fees.each do |fee|
          add_on = add_on(identifier: fee[add_on_identifier])

          result.not_found_failure!(resource: "add_on").raise_if_error! unless add_on
          result.single_validation_failure!(field: :boundaries, error_code: "values_are_invalid").raise_if_error! unless valid_boundaries?(fee)

          unit_amount_cents = fee[:unit_amount_cents] || add_on.amount_cents
          units = fee[:units]&.to_f || 1
          tax_codes = fee[:tax_codes]

          fee = Fee.new(
            invoice:,
            organization_id: invoice.organization_id,
            billing_entity_id: invoice.billing_entity_id,
            add_on:,
            invoice_display_name: fee[:invoice_display_name].presence,
            description: fee[:description] || add_on.description,
            unit_amount_cents:,
            amount_cents: (unit_amount_cents * units).round,
            precise_amount_cents: unit_amount_cents * units.to_d,
            amount_currency: invoice.currency,
            fee_type: :add_on,
            invoiceable_type: "AddOn",
            invoiceable: add_on,
            units:,
            payment_status: :pending,
            taxes_amount_cents: 0,
            taxes_precise_amount_cents: 0.to_d,
            properties: {
              from_datetime: from_datetime(fee),
              to_datetime: to_datetime(fee),
              timestamp: Time.current
            }
          )
          fee.precise_unit_amount = fee.unit_amount.to_f

          # Only apply explicit payload taxes here — they would be lost if deferred.
          # Derived taxes (from customer/plan hierarchy) and provider taxes are applied
          # later by ComputeTaxesAndTotalsService.
          if tax_codes.present?
            taxes_result = Fees::ApplyTaxesService.call(fee:, tax_codes:)
            taxes_result.raise_if_error!
          end

          fee.save!

          fees_result << fee
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

    delegate :customer, :organization, to: :invoice

    def add_on(identifier:)
      finder = api_context? ? :code : :id

      invoice.organization.add_ons.find_by(finder => identifier)
    end

    def add_on_identifier
      api_context? ? :add_on_code : :add_on_id
    end

    def valid_boundaries?(fee)
      return true if fee[:from_datetime].nil? && fee[:to_datetime].nil?

      fee[:from_datetime] &&
        fee[:to_datetime] &&
        Utils::Datetime.valid_format?(fee[:from_datetime]) &&
        Utils::Datetime.valid_format?(fee[:to_datetime]) &&
        from_datetime(fee) <= to_datetime(fee)
    end

    def from_datetime(fee)
      if fee[:from_datetime].is_a?(String)
        DateTime.iso8601(fee[:from_datetime])
      else
        fee[:from_datetime] || Time.current
      end
    end

    def to_datetime(fee)
      if fee[:to_datetime].is_a?(String)
        DateTime.iso8601(fee[:to_datetime])
      else
        fee[:to_datetime] || Time.current
      end
    end
  end
end
