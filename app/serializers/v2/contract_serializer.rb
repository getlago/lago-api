# frozen_string_literal: true

module V2
  # The agreement a customer signed: an optional plan (a plan-less contract
  # prices through directly attached rate cards), a validity window and the
  # billing anchor. There are no plan-interval fields — pricing lives on the
  # applied rate cards.
  class ContractSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        external_id: model.external_id,
        lago_customer_id: model.customer_id,
        external_customer_id: model.customer.external_id,
        name: model.name,
        plan_code: model.catalog_plan&.code,
        status: model.status,
        billing_time: model.billing_time,
        consolidate_invoice: model.consolidate_invoice,
        purchase_order_number: model.purchase_order_number,
        billing_anchor_date: model.billing_anchor_date&.iso8601,
        effective_billing_anchor_date: model.effective_billing_anchor_date&.iso8601,
        started_at: model.started_at&.iso8601,
        ended_at: model.ended_at&.iso8601,
        terminated_at: model.terminated_at&.iso8601,
        canceled_at: model.canceled_at&.iso8601,
        skip_invoice_custom_sections: model.skip_invoice_custom_sections,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        applied_rate_cards_count: applied_rate_cards_count
      }

      payload[:applied_rate_cards] = applied_rate_cards if include?(:applied_rate_cards)
      payload[:applied_invoice_custom_sections] = applied_invoice_custom_sections if include?(:applied_invoice_custom_sections)

      payload
    end

    private

    # The index passes one grouped count for the whole page; show falls back
    # to a count on the single record.
    def applied_rate_cards_count
      counts = options[:applied_rate_cards_counts]
      return counts.fetch(model.id, 0) if counts

      model.applied_rate_cards.count
    end

    def applied_rate_cards
      ::CollectionSerializer.new(
        model.applied_rate_cards.includes(:rate_phases, :rate_card, :contract),
        ::V2::ContractAppliedRateCardSerializer,
        collection_name: "applied_rate_cards",
        includes: nested_includes
      ).serialize[:applied_rate_cards]
    end

    # A section deleted before its links were cleaned up is skipped, not served as nil.
    def applied_invoice_custom_sections
      ::CollectionSerializer.new(
        model.applied_invoice_custom_sections.joins(:invoice_custom_section).includes(:invoice_custom_section),
        ::V1::AppliedInvoiceCustomSectionSerializer,
        collection_name: "applied_invoice_custom_sections"
      ).serialize[:applied_invoice_custom_sections]
    end
  end
end
