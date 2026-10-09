# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::EventTypesResolver do
  let(:expected_product_catalog_event_types) do
    %w[
      product_category.created product_category.updated product_category.deleted
      product.created product.updated product.deleted
      product_filter.created product_filter.updated product_filter.deleted
      rate_card.created rate_card.updated rate_card.deleted
      rate_card_rate.created rate_card_rate.updated rate_card_rate.deleted
      plan_rate_card.created plan_rate_card.updated plan_rate_card.deleted
      contract_rate_card.created contract_rate_card.updated contract_rate_card.deleted
      contract.created contract.updated contract.started contract.terminated contract.canceled
    ]
  end

  let(:required_permission) { "developers:manage" }
  let(:user) { create(:user) }
  let(:organization) { create(:organization) }
  let(:query) do
    <<~GQL
      query {
        eventTypes { name description category deprecated key }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires permission", "developers:manage"

  it "marks exactly the approved product catalog event types" do
    expect(product_catalog_event_types).to match_array(expected_product_catalog_event_types)
  end

  it "returns shared event types without product catalog options when the feature is disabled" do
    result = execute_graphql(
      current_user: user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    event_types_response = result["data"]["eventTypes"]
    expect(event_types_response.map { |event_type| event_type["name"] }).to match_array(
      WebhookEndpoint::WEBHOOK_EVENT_TYPES - product_catalog_event_types
    )
    expect(event_types_response.map { |event_type| event_type["name"] }).to include("plan.created", "plan.updated", "plan.deleted")
    expect(event_types_response.map { |event_type| event_type["name"] } & product_catalog_event_types).to be_empty
  end

  context "when product catalog is enabled" do
    let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }

    it "includes product catalog event types without requiring a premium license" do
      result = execute_graphql(
        current_user: user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      event_types_response = result["data"]["eventTypes"].map { |event_type| event_type["name"] }
      expect(event_types_response).to match_array(WebhookEndpoint::WEBHOOK_EVENT_TYPES)
      expect(event_types_response & product_catalog_event_types).to match_array(product_catalog_event_types)
    end
  end

  def product_catalog_event_types
    WebhookEndpoint::WEBHOOK_EVENT_TYPE_CONFIG.values.filter_map do |event_type|
      event_type[:name] if event_type[:product_catalog_only]
    end
  end
end
