# frozen_string_literal: true

module Sources
  # Batches RateCard#active_rate: one DISTINCT ON query resolves the latest
  # effective rate of every card on the page.
  class ActiveRate < GraphQL::Dataloader::Source
    def fetch(ids)
      rates = RateCardRate.effective
        .where(rate_card_id: ids)
        .select("DISTINCT ON (rate_card_id) rate_card_rates.*")
        .order("rate_card_id, effective_from DESC")
        .index_by(&:rate_card_id)

      ids.map { rates[it] }
    end
  end
end
