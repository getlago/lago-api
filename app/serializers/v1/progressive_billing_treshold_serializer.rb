# frozen_string_literal: true

module V1
  class ProgressiveBillingTresholdSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        treshold_display_name: model.treshold_display_name,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        recurring: model.recurring,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end
  end
end
