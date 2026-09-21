# frozen_string_literal: true

module Sources
  # Batches the resolved rate phases of contract cards across a page: the
  # cards' own phases in one query, their plan entries' phases in another,
  # then the rule ResolveRatePhasesService applies per card — own phases win
  # whole, else the plan entry's.
  #
  #   dataloader.with(Sources::ContractResolvedRatePhases).load(contract_rate_card)
  class ContractResolvedRatePhases < GraphQL::Dataloader::Source
    def fetch(cards)
      own = RatePhase.where(contract_rate_card_id: cards.map(&:id)).order(:position).group_by(&:contract_rate_card_id)
      plan_id_by_contract = Contract.where(id: cards.map(&:contract_id).uniq).pluck(:id, :catalog_plan_id).to_h
      plan_phases = plan_phases_by_entry(plan_id_by_contract.values.compact.uniq, cards.map(&:rate_card_id).uniq)

      cards.map do |card|
        own.fetch(card.id) { plan_phases.fetch([plan_id_by_contract[card.contract_id], card.rate_card_id], []) }
      end
    end

    private

    def plan_phases_by_entry(plan_ids, rate_card_ids)
      return {} if plan_ids.empty?

      PlanRateCard.where(catalog_plan_id: plan_ids, rate_card_id: rate_card_ids).includes(:rate_phases)
        .to_h { |entry| [[entry.catalog_plan_id, entry.rate_card_id], entry.rate_phases.to_a] }
    end
  end
end
