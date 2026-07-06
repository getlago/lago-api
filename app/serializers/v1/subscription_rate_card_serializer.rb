# frozen_string_literal: true

module V1
  class SubscriptionRateCardSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        external_subscription_id: model.subscription.external_id,
        rate_card_code: model.rate_card.code,
        units: model.units,
        started_at: model.started_at.iso8601,
        ended_at: model.ended_at&.iso8601,
        billing_anchor_date: model.billing_anchor_date.iso8601,
        next_billing_at: model.next_billing_at.iso8601,
        rate_phases_count: model.rate_phases.count,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end
  end
end
