# frozen_string_literal: true

module Invoices
  module Voids
    class RegenerateFromVoidedInvoiceService < BaseService

      def initialize(voided_invoice_id:, fees_ids: [])
        @voided_invoice_id = voided_invoice_id
        @fees = fees

        super
      end

      def call
        # PENDING: [25-06-12] - voided_invoice_id is mandatory until Raffi says otherwise.
        voided_invoice = Invoice.find_by(id: voided_invoice_id)
        return result.not_found_failure!(resource: "invoice") unless voided_invoice

        # We need to find the fees in the voided invoice to copy the taxes from them.
        # Perhaps we can use a more sofisticated approach to find the fees in the voided invoice.
        fees = voided_invoice.fees.where(id: fees_ids)
        return result.not_found_failure!(resource: "fees") unless fees.size == fees_ids.size

        ActiveRecord::Base.transaction do
          renegerated_invoice = create_generating_invoice(voided_invoice)
          result.invoice = renegerated_invoice

          # Duplicate each fee and copy its attributes
          fees.each do |fee|
            new_fee = fee.dup
            new_fee.invoice = renegerated_invoice
            new_fee.save!

            # Copy applied taxes from the original fee
            copy_applied_taxes(fee, new_fee)
          end

          # Finalize the invoice with the new fees
          finalize_invoice(renegerated_invoice)
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue => e
        result.fail_with_error!(e)
      end

      private

      attr_reader :voided_invoice_id, :fees

      def create_generating_invoice(voided_invoice)
        invoice_result = Invoices::CreateGeneratingService.call(
          voided_invoice: voided_invoice,
          customer: voided_invoice.customer,
          # TODO: [25-06-13] - Validade with Raffi if we should use always :one_off or copy the invoice type from the voided invoice.
          invoice_type: :one_off,
          currency: voided_invoice.currency,
          datetime: Time.current
        )
        invoice_result.raise_if_error!

        invoice_result.invoice
      end

      def copy_applied_taxes(source_fee, new_fee)
        source_fee.applied_taxes.each do |applied_tax|
          Fee::AppliedTax.create!(
            fee: new_fee,
            tax_id: applied_tax.tax_id,
            tax_description: applied_tax.tax_description,
            tax_code: applied_tax.tax_code,
            tax_name: applied_tax.tax_name,
            tax_rate: applied_tax.tax_rate,
            amount_cents: applied_tax.amount_cents,
            amount_currency: applied_tax.amount_currency,
            precise_amount_cents: applied_tax.precise_amount_cents
          )
        end
      end

      def finalize_invoice(invoice)
        # Compute amounts from fees
        Invoices::ComputeAmountsFromFees.call(invoice: invoice)

        # Apply custom sections if any
        Invoices::ApplyInvoiceCustomSectionsService.call(invoice: invoice)

        # Set payment status
        invoice.payment_status = invoice.total_amount_cents.positive? ? :pending : :succeeded

        # Transition to final status
        Invoices::TransitionToFinalStatusService.call(invoice: invoice)

        # Save the invoice
        invoice.save!
      end

      def establish_relationship(voided_invoice, renegerated_invoice)
        # Add metadata to link the invoices
        Invoices::Metadata::UpdateService.call(
          invoice: renegerated_invoice,
          metadata: {
            reissued_from: voided_invoice.id,
            reissued_at: Time.current.iso8601
          }
        )

        # You could also add metadata to the source invoice if needed
        Invoices::Metadata::UpdateService.call(
          invoice: voided_invoice,
          metadata: {
            reissued_to: renegerated_invoice.id,
            reissued_at: Time.current.iso8601
          }
        )
      end
    end
  end
end
