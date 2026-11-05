# frozen_string_literal: true

FactoryBot.define do
  factory :webhook_endpoint do
    organization
    webhook_url { Faker::Internet.url }

    # Product catalog organizations keep the jwt endpoints they created before the catalog,
    # so their specs can still create the default jwt endpoint.
    to_create do |endpoint|
      endpoint.save!(validate: !(endpoint.jwt? && endpoint.organization&.product_catalog_enabled?))
    end

    # An endpoint created before its organization stopped accepting its algorithm,
    # such as a jwt endpoint of a product catalog organization.
    trait :legacy_signature_algo do
      to_create { |endpoint| endpoint.save!(validate: false) }
    end

    trait :standard_webhooks do
      signature_algo { :standard_webhooks }

      # Organizations without the product catalog need the rollout flag to sign with Standard Webhooks.
      before(:create) do |endpoint|
        next if endpoint.allowed_signature_algos.include?("standard_webhooks")

        organization = endpoint.organization
        organization = Organization.find(organization.id) if organization.frozen?
        organization.enable_feature_flag!(:standard_webhooks_signature)
        endpoint.organization = organization
      end

      after(:create) do |endpoint|
        create(:webhook_endpoint_signing_key, webhook_endpoint: endpoint)
      end
    end
  end
end
