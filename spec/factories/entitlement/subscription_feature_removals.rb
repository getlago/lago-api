# frozen_string_literal: true

FactoryBot.define do
  factory :subscription_feature_removal, class: "Entitlement::SubscriptionFeatureRemoval" do
    organization { feature&.organization || association(:organization) }
    association :feature, factory: :feature
    subscription { association(:subscription, organization:) }
  end
end
