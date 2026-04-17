# frozen_string_literal: true

module V1
  class QuoteSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        status: model.status,
        order_type: model.order_type,
        number: model.number,
        version: model.version,
        currency: model.currency,
        description: model.description,
        content: model.content,
        legal_text: model.legal_text,
        internal_notes: model.internal_notes,
        auto_execute: model.auto_execute,
        billing_items: model.billing_items,
        commercial_terms: model.commercial_terms,
        contacts: model.contacts,
        metadata: model.metadata,
        approved_at: model.approved_at&.iso8601,
        voided_at: model.voided_at&.iso8601,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end
  end
end
