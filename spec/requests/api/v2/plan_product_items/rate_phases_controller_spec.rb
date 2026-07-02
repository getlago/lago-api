# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::PlanProductItems::RatePhasesController do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:plan_product_item) { create(:plan_product_item, organization:, plan:, rate_card:) }

  describe "GET /api/v2/plan_product_items/:plan_product_item_id/rate_phases" do
    subject { get_with_token(organization, "/api/v2/plan_product_items/#{plan_product_item.id}/rate_phases") }

    let!(:rate_phase) { create(:rate_phase, organization:, plan_product_item:, position: 1) }

    include_examples "requires API permission", "plan_product_item", "read"

    it "returns the entry's rate phases" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phases].map { |phase| phase[:lago_id] }).to eq([rate_phase.id])
    end

    context "when the plan product item does not exist" do
      subject { get_with_token(organization, "/api/v2/plan_product_items/#{SecureRandom.uuid}/rate_phases") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("plan_product_item")
      end
    end
  end

  describe "PUT /api/v2/plan_product_items/:plan_product_item_id/rate_phases" do
    subject do
      put_with_token(organization, "/api/v2/plan_product_items/#{plan_product_item.id}/rate_phases", {rate_phases: phases})
    end

    let(:phases) do
      [
        {position: 1, name: "trial", billing_interval_cycle_count: 3},
        {position: 2, name: "standard", billing_interval_cycle_count: nil}
      ]
    end

    include_examples "requires API permission", "plan_product_item", "write"

    it "replaces the phase sequence" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phases].map { |phase| phase[:position] }).to eq([1, 2])
      expect(json[:rate_phases].map { |phase| phase[:name] }).to eq(%w[trial standard])
    end

    context "when positions are not contiguous" do
      let(:phases) do
        [
          {position: 1, billing_interval_cycle_count: 3},
          {position: 3, billing_interval_cycle_count: nil}
        ]
      end

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
