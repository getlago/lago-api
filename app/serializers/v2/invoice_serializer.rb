# frozen_string_literal: true

module V2
  # An invoice billed from the product catalog: it names the contracts its
  # fees came from, not the v1 subscriptions and billing periods.
  class InvoiceSerializer < ModelSerializer
    DETAIL_INCLUDES = %i[contracts fees applied_taxes applied_invoice_custom_sections error_details].freeze

    def serialize
      payload = {
        lago_id: model.id,
        number: model.number,
        invoice_type:,
        status: model.status,
        payment_status: model.payment_status,
        billing_entity_code: model.billing_entity.code,
        lago_customer_id: model.customer_id,
        external_customer_id: model.customer.external_id,
        currency: model.currency,
        issuing_date: format_date(model.issuing_date),
        payment_due_date: format_date(model.payment_due_date),
        payment_overdue: model.payment_overdue,
        payment_dispute_lost_at: model.payment_dispute_lost_at&.iso8601,
        purchase_order_number: model.purchase_order_number,
        fees_amount_cents: model.fees_amount_cents,
        coupons_amount_cents: model.coupons_amount_cents,
        sub_total_excluding_taxes_amount_cents: model.sub_total_excluding_taxes_amount_cents,
        taxes_amount_cents: model.taxes_amount_cents,
        sub_total_including_taxes_amount_cents: model.sub_total_including_taxes_amount_cents,
        credit_notes_amount_cents: model.credit_notes_amount_cents,
        total_amount_cents: model.total_amount_cents,
        total_offsetted_credit_note_amount_cents: model.offset_amount_cents,
        total_paid_amount_cents: model.total_paid_amount_cents,
        total_due_amount_cents: model.total_due_amount_cents,
        file_url: model.file_url,
        xml_url: model.xml_url,
        voided_at: model.voided_at&.iso8601,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }

      payload[:contracts] = contracts if include?(:contracts)
      payload[:fees] = fees if include?(:fees)
      payload[:applied_taxes] = applied_taxes if include?(:applied_taxes)
      payload[:applied_invoice_custom_sections] = applied_invoice_custom_sections if include?(:applied_invoice_custom_sections)
      payload[:error_details] = error_details if include?(:error_details)

      payload
    end

    private

    def invoice_type
      model.advance_charges? ? "advance_fees" : model.invoice_type
    end

    # Fee provenance, not Invoice#contracts: a per-event pay-in-advance invoice
    # has no billing segment linking it to the contract.
    def contracts
      ::CollectionSerializer.new(
        Contract
          .where(organization_id: model.organization_id, id: model.fees.where.not(contract_id: nil).select(:contract_id))
          .order(:created_at, :id),
        ::V2::Invoices::ContractSerializer,
        collection_name: "contracts"
      ).serialize[:contracts]
    end

    def fees
      ::CollectionSerializer.new(
        model.fees.includes(::V2::FeeSerializer::PRELOADS).order(:created_at, :id),
        ::V2::FeeSerializer,
        collection_name: "fees"
      ).serialize[:fees]
    end

    def applied_taxes
      ::CollectionSerializer.new(
        model.applied_taxes.order(:created_at, :id),
        ::V2::Invoices::AppliedTaxSerializer,
        collection_name: "applied_taxes"
      ).serialize[:applied_taxes]
    end

    def applied_invoice_custom_sections
      ::CollectionSerializer.new(
        model.applied_invoice_custom_sections.order(:created_at, :id),
        ::V2::Invoices::AppliedInvoiceCustomSectionSerializer,
        collection_name: "applied_invoice_custom_sections"
      ).serialize[:applied_invoice_custom_sections]
    end

    def error_details
      ::CollectionSerializer.new(
        model.error_details.order(:created_at, :id),
        ::V2::ErrorDetailSerializer,
        collection_name: "error_details"
      ).serialize[:error_details]
    end
  end
end
