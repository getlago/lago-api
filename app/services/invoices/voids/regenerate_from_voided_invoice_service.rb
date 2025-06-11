# frozen_string_literal: true

module Invoices
  module Voids
    class RegenerateFromVoidedInvoiceService < BaseService

      def initialize(voided_invoice_id:)
        @voided_invoice_id = voided_invoice_id

        super
      end

      def call
        voided_invoice = Invoice.find_by(id: voided_invoice_id)
        return result.not_found_failure!(resource: "invoice") unless voided_invoice

        ActiveRecord::Base.transaction do
          renegerated_invoice = create_generating_invoice(voided_invoice)
          result.invoice = renegerated_invoice

          copy_fees(voided_invoice, renegerated_invoice)
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue => e
        result.fail_with_error!(e)
      end

      private

      attr_reader :voided_invoice_id

      def create_generating_invoice(voided_invoice)
        invoice_result = Invoices::CreateGeneratingService.call(
          customer: voided_invoice.customer,
          # Associate the voided invoice with the generating invoice
          voided_invoice: voided_invoice,
          invoice_type: :one_off,
          currency: voided_invoice.currency,
          datetime: Time.current
        )
        invoice_result.raise_if_error!

        invoice_result.invoice
      end

      def copy_fees(voided_invoice, renegerated_invoice)
        voided_invoice.fees.each do |source_fee|
          # Create a new fee with the same attributes as the source fee
          new_fee = Fee.new(
            invoice: renegerated_invoice,
            organization_id: source_fee.organization_id,
            billing_entity_id: source_fee.billing_entity_id,
            subscription_id: source_fee.subscription_id,
            charge_id: source_fee.charge_id,
            add_on_id: source_fee.add_on_id,
            applied_add_on_id: source_fee.applied_add_on_id,
            charge_filter_id: source_fee.charge_filter_id,
            group_id: source_fee.group_id,
            invoiceable_type: source_fee.invoiceable_type,
            invoiceable_id: source_fee.invoiceable_id,
            amount_cents: source_fee.amount_cents,
            amount_currency: source_fee.amount_currency,
            precise_amount_cents: source_fee.precise_amount_cents,
            units: source_fee.units,
            total_aggregated_units: source_fee.total_aggregated_units,
            unit_amount_cents: source_fee.unit_amount_cents,
            precise_unit_amount: source_fee.precise_unit_amount,
            events_count: source_fee.events_count,
            payment_status: :pending,
            fee_type: source_fee.fee_type,
            invoice_display_name: source_fee.invoice_display_name,
            description: source_fee.description,
            properties: source_fee.properties,
            grouped_by: source_fee.grouped_by,
            taxes_amount_cents: 0,
            taxes_precise_amount_cents: 0.to_d,
            amount_details: source_fee.amount_details
          )

          new_fee.save!

          copy_applied_taxes(source_fee, new_fee)
        end
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
