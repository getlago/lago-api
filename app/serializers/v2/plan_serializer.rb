# frozen_string_literal: true

module V2
  # Catalog plan shape: no legacy pricing fields (interval, amount_cents,
  # pay_in_advance) — the billing cadence lives on the applied rate cards.
  class PlanSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        invoice_display_name: model.invoice_display_name,
        code: model.code,
        description: model.description,
        currency: model.amount_currency,
        applied_rate_cards_count: model.applied_rate_cards.count,
        created_at: model.created_at.iso8601
      }
    end
  end
end
