# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::CatalogPlans::Object do
  subject { described_class }

  it { is_expected.to have_field(:metadata).of_type("[ItemMetadata!]") }

  describe "#metadata" do
    subject(:metadata) { run_graphql_field("CatalogPlan.metadata", catalog_plan) }

    let(:catalog_plan) { create(:catalog_plan) }

    it "returns nil without metadata" do
      expect(metadata).to be_nil
    end

    context "with metadata" do
      before do
        create(:item_metadata, owner: catalog_plan, organization: catalog_plan.organization, value: {"crm_id" => "123", "tier" => nil})
      end

      it "returns the key-value pairs" do
        expect(metadata).to eq({"crm_id" => "123", "tier" => nil})
      end
    end
  end
end
