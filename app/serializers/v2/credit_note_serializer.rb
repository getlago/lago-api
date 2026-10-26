# frozen_string_literal: true

module V2
  class CreditNoteSerializer < ModelSerializer
    expandable :items, serializer: ::V2::CreditNotes::ItemSerializer
    expandable :applied_taxes, serializer: ::V2::CreditNotes::AppliedTaxSerializer
    expandable :customer, serializer: ::V2::CustomerSerializer
    expandable :error_details, serializer: ::V1::ErrorDetailSerializer
    expandable :metadata, serializer: ::V1::MetadataSerializer

    def serialize
      {
        lago_id: model.id,
        billing_entity_code: model.invoice.billing_entity.code,
        sequential_id: model.sequential_id,
        number: model.number,
        lago_invoice_id: model.invoice_id,
        invoice_number: model.invoice.number,
        purchase_order_number: model.purchase_order_number,
        issuing_date: format_date(model.issuing_date),
        credit_status: model.credit_status,
        refund_status: model.refund_status,
        reason: model.reason,
        description: model.description,
        currency: model.currency,
        sub_total_excluding_taxes_amount_cents: model.sub_total_excluding_taxes_amount_cents,
        taxes_amount_cents: model.taxes_amount_cents,
        sub_total_including_taxes_amount_cents: model.sub_total_excluding_taxes_amount_cents + model.taxes_amount_cents,
        total_amount_cents: model.total_amount_cents,
        balance_amount_cents: model.balance_amount_cents,
        credit_amount_cents: model.credit_amount_cents,
        refund_amount_cents: model.refund_amount_cents,
        offset_amount_cents: model.offset_amount_cents,
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at),
        file_url: model.file_url,
        xml_url: model.xml_url,
        self_billed: model.invoice.self_billed
      }
    end

    private

    def items
      model.items.sort_by { [it.created_at, it.id] }
    end

    def applied_taxes
      model.applied_taxes.sort_by { [it.created_at, it.id] }
    end
  end
end
