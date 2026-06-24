# frozen_string_literal: true

require "rails_helper"

module RequiresProductCatalogSpec
  class ThingType < Types::BaseObject
    field :ok, Boolean, null: false
  end

  class GuardedMutation < Mutations::BaseMutation
    include RequiresProductCatalog

    graphql_name "GuardedByProductCatalog"
    type ThingType

    def current_organization
      context[:current_organization]
    end

    def resolve(**args)
      {ok: true}
    end
  end

  class MutationType < Types::BaseObject
    field :guarded, mutation: GuardedMutation
  end

  class TestSchema < LagoApiSchema
    mutation(MutationType)
  end
end

RSpec.describe RequiresProductCatalog do
  subject(:result) do
    RequiresProductCatalogSpec::TestSchema.execute(
      "mutation { guarded(input: {}) { ok } }",
      context: {current_organization: organization}
    )
  end

  let(:organization) { create(:organization, premium_integrations:) }
  let(:premium_integrations) { [] }

  context "when the organization is not on the product catalog" do
    it "returns a forbidden error" do
      expect(result["errors"].first["extensions"]["code"]).to eq("feature_unavailable")
    end
  end

  context "when the organization is on the product catalog", :premium do
    let(:premium_integrations) { ["product_catalog"] }

    it "allows the mutation" do
      expect(result["data"]["guarded"]["ok"]).to be(true)
    end
  end
end
