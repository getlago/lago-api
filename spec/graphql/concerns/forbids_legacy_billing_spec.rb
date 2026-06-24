# frozen_string_literal: true

require "rails_helper"

module ForbidsLegacyBillingSpec
  class ThingType < Types::BaseObject
    field :ok, Boolean, null: false
  end

  class GuardedMutation < Mutations::BaseMutation
    include ForbidsLegacyBilling

    graphql_name "ForbiddenWhenProductCatalog"
    type ThingType

    def current_organization
      context[:current_organization]
    end

    def resolve(**args)
      {ok: true}
    end
  end

  class MutationType < Types::BaseObject
    field :legacy, mutation: GuardedMutation
  end

  class TestSchema < LagoApiSchema
    mutation(MutationType)
  end
end

RSpec.describe ForbidsLegacyBilling do
  subject(:result) do
    ForbidsLegacyBillingSpec::TestSchema.execute(
      "mutation { legacy(input: {}) { ok } }",
      context: {current_organization: organization}
    )
  end

  let(:organization) { create(:organization, premium_integrations:) }
  let(:premium_integrations) { [] }

  context "when the organization is on the product catalog", :premium do
    let(:premium_integrations) { ["product_catalog"] }

    it "blocks the legacy mutation" do
      expect(result["errors"].first["extensions"]["code"]).to eq("legacy_billing_disabled")
    end
  end

  context "when the organization is not on the product catalog" do
    it "allows the legacy mutation" do
      expect(result["data"]["legacy"]["ok"]).to be(true)
    end
  end
end
