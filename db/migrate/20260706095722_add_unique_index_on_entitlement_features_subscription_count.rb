# frozen_string_literal: true

class AddUniqueIndexOnEntitlementFeaturesSubscriptionCount < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :entitlement_features_subscriptions_count, :entitlement_feature_id, unique: true, algorithm: :concurrently
  end
end
