# frozen_string_literal: true

module V2
  class CatalogPlanSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        name: model.name,
        invoice_display_name: model.invoice_display_name,
        code: model.code,
        description: model.description,
        currency: model.currency,
        applied_rate_cards_count: model.applied_rate_cards.size,
        created_at: model.created_at.iso8601
      }

      payload.merge!(taxes) if include?(:taxes)
      payload
    end

    private

    def taxes
      ::CollectionSerializer.new(
        model.taxes,
        ::V1::TaxSerializer,
        collection_name: "taxes"
      ).serialize
    end
  end
end
