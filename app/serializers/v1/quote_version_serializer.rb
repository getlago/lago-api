# frozen_string_literal: true

module V1
  class QuoteVersionSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        quote_id: model.quote_id,
        version: model.version,
        number: model.quote.number,
        status: model.status,
        void_reason: model.void_reason,
        voided_at: model.voided_at&.iso8601,
        approved_at: model.approved_at&.iso8601,
        created_at: model.created_at.iso8601
      }
    end
  end
end
