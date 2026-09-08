# frozen_string_literal: true

module V2
  # The agreement a customer signed: an optional plan (a plan-less contract
  # prices through directly attached rate cards), a validity window and the
  # billing anchor. There are no plan-interval fields — pricing lives on the
  # applied rate cards.
  class ContractSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        external_id: model.external_id,
        lago_customer_id: model.customer_id,
        external_customer_id: model.customer.external_id,
        name: model.name,
        plan_code: model.plan&.code,
        status: model.status,
        billing_time: model.billing_time,
        billing_anchor_date: model.billing_anchor_date&.iso8601,
        started_at: model.started_at&.iso8601,
        ended_at: model.ended_at&.iso8601,
        terminated_at: model.terminated_at&.iso8601,
        canceled_at: model.canceled_at&.iso8601,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        applied_rate_cards_count: applied_rate_cards_count
      }

      payload[:applied_rate_cards] = applied_rate_cards if include?(:applied_rate_cards)

      payload
    end

    private

    # The index passes one grouped count for the whole page; show falls back
    # to the scoped count on the single record. Ended attachments are history,
    # not cards the contract currently carries.
    def applied_rate_cards_count
      counts = options[:applied_rate_cards_counts]
      return counts.fetch(model.id, 0) if counts

      model.applied_rate_cards.current_and_scheduled.count
    end

    def applied_rate_cards
      ::CollectionSerializer.new(
        model.applied_rate_cards.current_and_scheduled.includes(:rate_phases, :rate_card, :contract),
        ::V2::ContractAppliedRateCardSerializer,
        collection_name: "applied_rate_cards"
      ).serialize[:applied_rate_cards]
    end
  end
end
