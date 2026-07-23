# frozen_string_literal: true

class SubscriptionRateCardsQuery < BaseQuery
  Result = BaseResult[:subscription_rate_cards]
  Filters = BaseFilters[:subscription_id, :external_subscription_id]

  def call
    subscription_rate_cards = base_scope
    subscription_rate_cards = with_subscription(subscription_rate_cards) if filters.subscription_id.present?
    subscription_rate_cards = with_external_subscription(subscription_rate_cards) if filters.external_subscription_id.present?
    subscription_rate_cards = paginate(subscription_rate_cards)
    subscription_rate_cards = apply_consistent_ordering(subscription_rate_cards)

    result.subscription_rate_cards = subscription_rate_cards
    result
  end

  private

  def base_scope
    SubscriptionRateCard.where(organization:)
  end

  def with_subscription(scope)
    scope.where(subscription_id: filters.subscription_id)
  end

  def with_external_subscription(scope)
    scope.joins(:subscription).where(subscriptions: {external_id: filters.external_subscription_id})
  end
end
