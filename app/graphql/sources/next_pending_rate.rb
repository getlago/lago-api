# frozen_string_literal: true

module Sources
  # Batches RateCard#rates filtered after `as_of`: one DISTINCT ON query
  # resolves the soonest not-yet-effective rate of every card on the page,
  # relative to whatever perspective the caller asks for (defaults to now).
  class NextPendingRate < GraphQL::Dataloader::Source
    def initialize(as_of)
      @as_of = as_of
    end

    def fetch(ids)
      rates = RateCardRate.where("effective_from > ?", @as_of)
        .where(rate_card_id: ids)
        .select("DISTINCT ON (rate_card_id) rate_card_rates.*")
        .order("rate_card_id, effective_from ASC")
        .index_by(&:rate_card_id)

      ids.map { rates[it] }
    end
  end
end
