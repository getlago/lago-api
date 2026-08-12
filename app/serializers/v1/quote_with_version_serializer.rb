# frozen_string_literal: true

module V1
  # Webhook payload for the quote lifecycle events, built from the version the event happened to.
  # QuoteSerializer cannot serve here: it embeds `current_version`, resolved when the payload is
  # rendered. A clone voids a version and creates its replacement in the same transaction, so by
  # delivery time `current_version` names the new draft rather than the version that was voided.
  class QuoteWithVersionSerializer < ModelSerializer
    def serialize
      {
        lago_id: quote.id,
        number: quote.number,
        order_type: quote.order_type,
        lago_customer_id: quote.customer_id,
        lago_subscription_id: quote.subscription_id,
        lago_organization_id: quote.organization_id,
        created_at: quote.created_at.iso8601,
        updated_at: quote.updated_at.iso8601,
        version: ::V1::QuoteVersionSerializer.new(model).serialize
      }
    end

    private

    def quote
      model.quote
    end
  end
end
