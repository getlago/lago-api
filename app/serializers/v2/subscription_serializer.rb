# frozen_string_literal: true

module V2
  # The v2 shape drops the plan-interval fields (amounts, billing periods,
  # trial): a product-catalog subscription prices through its rate card
  # entries, each carrying its own billing cycle.
  class SubscriptionSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        external_id: model.external_id,
        lago_customer_id: model.customer_id,
        external_customer_id: model.customer.external_id,
        name: model.name,
        plan_code: model.plan.code,
        status: model.status,
        billing_time: model.billing_time,
        subscription_at: model.subscription_at&.iso8601,
        started_at: model.started_at&.iso8601,
        ending_at: model.ending_at&.iso8601,
        terminated_at: model.terminated_at&.iso8601,
        canceled_at: model.canceled_at&.iso8601,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        applied_rate_cards_count: model.applied_rate_cards.count
      }

      payload[:applied_rate_cards] = applied_rate_cards if include?(:applied_rate_cards)

      payload
    end

    private

    def applied_rate_cards
      ::CollectionSerializer.new(
        model.applied_rate_cards,
        ::V1::SubscriptionRateCardSerializer,
        collection_name: "applied_rate_cards"
      ).serialize[:applied_rate_cards]
    end
  end
end
