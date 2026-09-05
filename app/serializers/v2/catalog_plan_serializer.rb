# frozen_string_literal: true

module V2
  class CatalogPlanSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        invoice_display_name: model.invoice_display_name,
        code: model.code,
        description: model.description,
        currency: model.currency,
        # Rate cards attach to catalog plans in a later slice; until then it is always 0.
        applied_rate_cards_count: 0,
        created_at: model.created_at.iso8601
      }
    end
  end
end
