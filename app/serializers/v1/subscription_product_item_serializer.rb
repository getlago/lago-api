# frozen_string_literal: true

module V1
  class SubscriptionProductItemSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_subscription_id: model.subscription_id,
        lago_product_item_id: model.product_item_id,
        billing_anchor_date: model.billing_anchor_date&.iso8601,
        started_at: model.started_at&.iso8601,
        ended_at: model.ended_at&.iso8601,
        next_billing_at: model.next_billing_at&.iso8601,
        units: model.units,
        created_at: model.created_at.iso8601
      }
    end
  end
end
