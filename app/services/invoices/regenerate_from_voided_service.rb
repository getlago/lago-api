# frozen_string_literal: true

module Invoices
  class RegenerateFromVoidedService < BaseService
    def initialize(voided_invoice:, fees:)
      @voided_invoice = voided_invoice
      @fees = fees
      super
    end

    activity_loggable(
      action: "invoice.regenerated_from_voided",
      record: -> { voided_invoice }
    )

    def call
      return result.not_found_failure!(resource: "invoice") unless voided_invoice
      return result.not_allowed_failure!(code: "not_voided") unless voided_invoice.voided?
      return result.not_allowed_failure!(code: "already_regenerated") if voided_invoice.regenerated_invoice.present?

      existing_fees = voided_invoice.fees.where(id: fees.map { |fee| fee[:id] })
      new_fees = fees.select { |fee| fee[:id].blank? }

      ActiveRecord::Base.transaction do
        generating_result = Invoices::CreateGeneratingService.call(
          customer: voided_invoice.customer,
          invoice_type: voided_invoice.invoice_type,
          currency: voided_invoice.currency,
          datetime: voided_invoice.created_at,
          voided_invoice_id: voided_invoice.id
        )

        generating_result.raise_if_error!
        regenerated_invoice = generating_result.invoice

        # rubocop:disable Rails/SkipsModelValidations
        voided_invoice.invoice_subscriptions.update_all(invoice_id: regenerated_invoice.id)
        # rubocop:enable Rails/SkipsModelValidations

        existing_fees.each do |fee_record|
          fee_record.dup.tap do |fee|
            fee.invoice = regenerated_invoice
            fee.payment_status = :pending
            fee.taxes_amount_cents = 0
            fee.taxes_precise_amount_cents = 0.to_d

            fee_input = fees.find { |f| f[:id] == fee_record.id }
            if fee_input
              allowed_attrs = %i[
                charge_id
                subscription_id
                invoice_display_name
                units
                description
                amount_cents
                unit_amount_cents
                add_on_id
              ]
              allowed_attrs.each do |attr|
                fee[attr] = fee_input[attr] if fee_input.key?(attr)
              end
            end

            fee.save!

            taxes_result = Fees::ApplyTaxesService.call(fee: fee)
            taxes_result.raise_if_error!
          end
        end

        new_fees.each do |fee_attributes|
          fee_data = fee_attributes.merge(
            invoice: regenerated_invoice,
            organization: regenerated_invoice.organization,
            billing_entity: regenerated_invoice.billing_entity,
            amount_cents: fee_attributes.fetch(:unit_amount_cents, 0),
            unit_amount_cents: fee_attributes[:unit_amount_cents],
            amount_currency: regenerated_invoice.currency,
            fee_type: fee_attributes[:add_on_id].present? ? :add_on : :charge,
            taxes_amount_cents: 0, # To be calculated on ApplyTaxesService
            taxes_precise_amount_cents: 0.to_d, # To be calculated on ApplyTaxesService
            payment_status: :pending,
            total_aggregated_units: fee_attributes[:total_aggregated_units]
          )

          new_fee = Fee.create!(fee_data)

          taxes_result = Fees::ApplyTaxesService.call(fee: new_fee)
          taxes_result.raise_if_error!
        end

        amounts_from_fees_result = Invoices::ComputeAmountsFromFees.call(invoice: regenerated_invoice)
        amounts_from_fees_result.raise_if_error!

        if voided_invoice.customer.applicable_invoice_grace_period.positive?
          regenerated_invoice.draft!
        else
          transition_result = Invoices::TransitionToFinalStatusService.call(invoice: regenerated_invoice)
          transition_result.raise_if_error!
          regenerated_invoice.save!
        end

        result.invoice = regenerated_invoice
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    rescue => e
      result.service_failure!(code: "unexpected_error", message: e.message)
    end

    private

    attr_reader :voided_invoice, :fees
  end
end
