# frozen_string_literal: true

module Sources
  # Batches a contract's applied rate cards across a collection:
  # `contracts { appliedRateCards, appliedRateCardsCount }` runs one grouped
  # query for the whole page instead of one per contract; both the list and
  # the count field read the same loaded set.
  #
  #   dataloader.with(Sources::ContractCurrentRateCards).load(object.id)
  class ContractCurrentRateCards < GraphQL::Dataloader::Source
    def fetch(contract_ids)
      by_contract = ContractRateCard
        .where(contract_id: contract_ids)
        .includes(:rate_card)
        .order(:effective_date, :id)
        .group_by(&:contract_id)

      contract_ids.map { by_contract.fetch(it, []) }
    end
  end
end
