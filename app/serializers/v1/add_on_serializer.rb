# frozen_string_literal: true

module V1
  class AddOnSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        created_at: model.created_at.iso8601,
        description: model.description
      }
    end
  end
end
