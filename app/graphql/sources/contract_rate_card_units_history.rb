# frozen_string_literal: true

module Sources
  class ContractRateCardUnitsHistory < GraphQL::Dataloader::Source
    def fetch(cards)
      ActiveRecord::Associations::Preloader.new(records: cards, associations: :organization).call
      histories = cards.group_by(&:organization).each_with_object({}) do |(organization, records), result|
        result.merge!(::ContractRateCardUnitsHistoryQuery.call!(organization:, contract_rate_cards: records).histories)
      end
      cards.map { histories.fetch(it.id) }
    end
  end
end
