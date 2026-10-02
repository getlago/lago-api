# frozen_string_literal: true

module V2
  # The agreement a customer signed: an optional plan (a plan-less contract
  # prices through directly attached rate cards), a validity window and the
  # billing anchor. There are no plan-interval fields — pricing lives on the
  # applied rate cards.
  class ContractSerializer < ModelSerializer
    EXPANDABLE_RELATIONS = {
      # One card per rate card the contract prices.
      applied_rate_cards: nil,
      plan: :catalog_plan,
      customer: {customer: :billing_entity}
    }.freeze

    def self.expandable_relations
      EXPANDABLE_RELATIONS
    end

    def serialize
      {
        lago_id: model.id,
        external_id: model.external_id,
        lago_customer_id: model.customer_id,
        external_customer_id: model.customer.external_id,
        name: model.name,
        plan_code: model.catalog_plan&.code,
        status: model.status,
        billing_time: model.billing_time,
        billing_anchor_date: model.billing_anchor_date&.iso8601,
        started_at: model.started_at&.iso8601,
        ended_at: model.ended_at&.iso8601,
        terminated_at: model.terminated_at&.iso8601,
        canceled_at: model.canceled_at&.iso8601,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        **expanded_payload
      }
    end

    private

    # In the order of /applied_rate_cards.
    def expand_applied_rate_cards
      model.applied_rate_cards.preload(:rate_card, :contract).order(::CursorPagination::DEFAULT_SORT).map do |applied_rate_card|
        ::V2::ContractAppliedRateCardSerializer.new(applied_rate_card, includes: nested_includes).serialize
      end
    end

    # Both associations read with_discarded, so that a discarded plan or customer carries its deleted_at.
    def expand_plan
      model.catalog_plan&.then { ::V2::CatalogPlanSerializer.new(it, includes: nested_includes).serialize }
    end

    def expand_customer
      ::V2::CustomerSerializer.new(model.customer, includes: nested_includes).serialize
    end
  end
end
