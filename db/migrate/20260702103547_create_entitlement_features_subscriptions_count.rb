# frozen_string_literal: true

class CreateEntitlementFeaturesSubscriptionsCount < ActiveRecord::Migration[8.0]
  def change
    create_view :entitlement_features_subscriptions_count, materialized: true
  end
end
