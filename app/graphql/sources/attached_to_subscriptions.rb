# frozen_string_literal: true

module Sources
  # Batches RateCard#attached_to_subscriptions?: a card bills someone through
  # a direct contract attachment or through a catalog plan that has contracts,
  # canceled contracts aside.
  class AttachedToSubscriptions < GraphQL::Dataloader::Source
    def fetch(ids)
      attached = ContractRateCard.joins(:contract).merge(Contract.not_canceled)
        .where(rate_card_id: ids).distinct.pluck(:rate_card_id) |
        PlanRateCard.where(rate_card_id: ids, catalog_plan_id: Contract.not_canceled.select(:catalog_plan_id))
          .distinct.pluck(:rate_card_id)

      ids.map { attached.include?(it) }
    end
  end
end
