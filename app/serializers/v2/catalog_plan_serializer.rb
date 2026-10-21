# frozen_string_literal: true

module V2
  class CatalogPlanSerializer < ModelSerializer
    expandable :taxes, serializer: ::V2::TaxSerializer

    def serialize
      {
        lago_id: model.id,
        name: model.name,
        invoice_display_name: model.invoice_display_name,
        code: model.code,
        description: model.description,
        currency: model.currency,
        **counts,
        created_at: model.created_at.iso8601,
        deleted_at: model.deleted_at&.iso8601
      }
    end

    private

    # Only for the plan webhooks, which keep the count they have always sent.
    def counts = include?(:counts) ? {applied_rate_cards_count: model.applied_rate_cards.size} : {}

    # The kept taxes, latest linked first.
    def taxes = model.taxes.merge(::Plan::AppliedTax.order(::CursorPagination::DEFAULT_SORT))
  end
end
