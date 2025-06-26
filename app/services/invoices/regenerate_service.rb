# frozen_string_literal: true

module Invoices
  class RegenerateService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:, fees:)
      @invoice = invoice
      @fees_attrs = fees
      super()
    end

    def call
      return result.not_found_failure!(resource: "invoice") if invoice.nil?
      return result.not_allowed_failure!(code: "not_voided") unless invoice.voided?

      ActiveRecord::Base.transaction do
        new_invoice = create_new_invoice!

        fees_attrs.each do |attrs|
          create_fee!(new_invoice, attrs.with_indifferent_access)
        end

        Invoices::ComputeAmountsFromFees.call(invoice:)
        Invoices::ApplyInvoiceCustomSectionsService.call(invoice:)
        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded
        Invoices::TransitionToFinalStatusService.call(invoice:)
        invoice.save!

        result.invoice = invoice
      end

      result
    end

    private

    attr_reader :invoice, :fees_attrs

    def create_new_invoice!
      creation_result = Invoices::CreateGeneratingService.call(
        customer: invoice.customer,
        invoice_type: invoice.invoice_type,
        currency: invoice.currency,
        datetime: Time.current,
        skip_charges: true
      )

      creation_result.raise_if_error!

      new_invoice = creation_result.invoice
      new_invoice.update!(voided_invoice_id: invoice.id, status: :draft)

      new_invoice
    end

    def create_fee!(new_invoice, attrs)
      if attrs[:fee_id].present?
        duplicate_fee!(new_invoice, attrs)
      else
        create_new_fee!(new_invoice, attrs)
      end
    end

    # Duplicate an existing fee from the voided invoice, applying overrides from attrs
    def duplicate_fee!(new_invoice, attrs)
      previous_fee = invoice.fees.find_by(id: attrs[:fee_id])
      unless previous_fee
        result.not_found_failure!(resource: "fee")
        raise BaseService::FailedResult.new(result, "fee_not_found")
      end

      new_fee = previous_fee.dup
      new_fee.invoice = new_invoice
      new_fee.units = attrs[:units] if attrs.key?(:units)

      if attrs[:unit_precise_amount].present?
        new_fee.precise_unit_amount = attrs[:unit_precise_amount]
        new_fee.unit_amount_cents = (attrs[:unit_precise_amount].to_f * previous_fee.amount.currency.subunit_to_unit).round
      end

      new_fee.invoice_display_name = attrs[:invoice_display_name] if attrs[:invoice_display_name]

      new_fee.save!
    end

    # Use existing AdjustedFees::CreateService to create a brand-new fee on the invoice
    def create_new_fee!(new_invoice, attrs)
      params = {
        charge_id: attrs[:charge_id],
        subscription_id: attrs[:subscription_id],
        units: attrs[:units],
        unit_precise_amount: attrs[:unit_precise_amount],
        invoice_display_name: attrs[:invoice_display_name]
      }.compact

      AdjustedFees::CreateService.call!(invoice: new_invoice, params: params)
    end
  end
end
