# frozen_string_literal: true

module Sources
  # Batches RateCard#rates.pending: one DISTINCT ON query resolves the soonest
  # not-yet-effective rate of every card on the page.
  class PendingRate < GraphQL::Dataloader::Source
    def fetch(ids)
      rates = RateCardRate.pending
        .where(rate_card_id: ids)
        .select("DISTINCT ON (rate_card_id) rate_card_rates.*")
        .order("rate_card_id, effective_from ASC")
        .index_by(&:rate_card_id)

      ids.map { rates[it] }
    end
  end
end
