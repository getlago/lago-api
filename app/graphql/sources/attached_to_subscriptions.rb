# frozen_string_literal: true

module Sources
  # Batches RateCard#attached_to_subscriptions?: a card bills someone through
  # a direct contract attachment or through a plan that has contracts. The
  # Subscription check stays for catalog plans subscribed through v1 before
  # contracts existed.
  class AttachedToSubscriptions < GraphQL::Dataloader::Source
    def fetch(ids)
      attached = ContractRateCard.where(rate_card_id: ids).distinct.pluck(:rate_card_id) |
        PlanRateCard.where(rate_card_id: ids, plan_id: Contract.select(:plan_id)).distinct.pluck(:rate_card_id) |
        PlanRateCard.where(rate_card_id: ids, plan_id: Subscription.select(:plan_id)).distinct.pluck(:rate_card_id)

      ids.map { attached.include?(it) }
    end
  end
end
