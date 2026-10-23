# frozen_string_literal: true

module V2
  # The agreement a customer signed: an optional plan (a plan-less contract
  # prices through directly attached rate cards), a validity window and the
  # billing anchor. There are no plan-interval fields — pricing lives on the
  # applied rate cards.
  class ContractSerializer < ModelSerializer
    expandable :applied_rate_cards, serializer: ::V2::ContractAppliedRateCardSerializer
    expandable :plan, serializer: ::V2::CatalogPlanSerializer
    # Read with_discarded, so that a deleted customer expands with its deleted_at.
    expandable :customer, serializer: ::V2::CustomerSerializer
    expandable :invoice_custom_sections, serializer: ::V2::InvoiceCustomSectionSerializer

    def serialize
      {
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
    end

    private

    # The index passes one grouped count for the whole page; show falls back
    # to a count on the single record, or the cards a caller preloaded.
    def applied_rate_cards_count
      counts = options[:applied_rate_cards_counts]
      return counts.fetch(model.id, 0) if counts

      model.applied_rate_cards.size
    end

    # As /applied_rate_cards lists them, with what each card renders.
    def applied_rate_cards
      model.applied_rate_cards.preload(:rate_card, :contract, :rate_phases).order(::CursorPagination::DEFAULT_SORT)
    end

    # Read with_discarded, so that a deleted plan expands with its deleted_at.
    def plan = model.catalog_plan

    # The selected sections, the last selected first. Their default scope leaves out a section
    # deleted while its link remains.
    def invoice_custom_sections
      model.selected_invoice_custom_sections.merge(::Contract::AppliedInvoiceCustomSection.order(::CursorPagination::DEFAULT_SORT))
    end
  end
end
