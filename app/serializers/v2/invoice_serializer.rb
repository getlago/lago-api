# frozen_string_literal: true

module V2
  # An invoice billed from the product catalog: it names the contracts its
  # fees came from, not the v1 subscriptions and billing periods.
  class InvoiceSerializer < ModelSerializer
    expandable :fees, serializer: ::V2::FeeSerializer
    expandable :applied_taxes, serializer: ::V2::Invoices::AppliedTaxSerializer
    expandable :customer, serializer: ::V2::CustomerSerializer
    expandable :contracts, serializer: ::V2::ContractSerializer
    expandable :applied_invoice_custom_sections, serializer: ::V2::Invoices::AppliedInvoiceCustomSectionSerializer
    expandable :error_details, serializer: ::V2::ErrorDetailSerializer

    # A webhook cannot ask for expansions: it carries everything but the fees, so that its size
    # does not grow with the invoice. A consumer reads the fees through the API.
    WEBHOOK_INCLUDES = %i[applied_taxes contracts applied_invoice_custom_sections error_details].freeze

    def serialize
      {
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
    end

    private

    def invoice_type
      model.advance_charges? ? "advance_fees" : model.invoice_type
    end

    # Product fees only: an invoice of another type that holds one is a catalog invoice too,
    # and its legacy fees are not v2 fees.
    def fees
      model.fees.product.preload(::V2::FeeSerializer::PRELOADS).order(:created_at, :id)
    end

    def applied_taxes
      model.applied_taxes.order(:created_at, :id)
    end

    # Fee provenance, not Invoice#contracts: a per-event pay-in-advance invoice
    # has no billing segment linking it to the contract.
    def contracts
      Contract
        .where(organization_id: model.organization_id, id: model.fees.where.not(contract_id: nil).select(:contract_id))
        .preload({customer: :billing_entity}, :catalog_plan, :applied_rate_cards)
        .order(:created_at, :id)
    end

    def applied_invoice_custom_sections
      model.applied_invoice_custom_sections.order(:created_at, :id)
    end

    def error_details
      model.error_details.order(:created_at, :id)
    end
  end
end
