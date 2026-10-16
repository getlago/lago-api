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
        **counts,
        created_at: model.created_at.iso8601,
        **deleted_at_payload
      }
    end

    private

    def counts = include?(:counts) ? {applied_rate_cards_count: model.applied_rate_cards.size} : {}
  end
end
