# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanProductItemsQuery, type: :query do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:plan) { create(:plan, organization:) }
  let!(:plan_product_item) { create(:plan_product_item, organization:, plan:) }
  let!(:other_plan_product_item) { create(:plan_product_item, organization:) }

  it "returns all plan product items of the organization" do
    expect(result).to be_success
    expect(result.plan_product_items).to match_array([plan_product_item, other_plan_product_item])
  end

  context "when filtering by plan_id" do
    let(:filters) { {plan_id: plan.id} }

    it "returns only the plan's product items" do
      expect(result.plan_product_items).to eq([plan_product_item])
    end
  end
end
