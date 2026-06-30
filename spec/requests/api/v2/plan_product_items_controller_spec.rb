# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::PlanProductItemsController do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }

  describe "POST /api/v2/plan_product_items" do
    subject { post_with_token(organization, "/api/v2/plan_product_items", {plan_product_item: create_params}) }

    let(:create_params) do
      {plan_id: plan.id, rate_card_code: rate_card.code, units: "10"}
    end

    include_examples "requires API permission", "plan_product_item", "write"

    it "assigns the rate card to the plan with a default rate phase" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan_product_item][:lago_id]).to be_present
      expect(json[:plan_product_item][:lago_plan_id]).to eq(plan.id)
      expect(json[:plan_product_item][:lago_rate_card_id]).to eq(rate_card.id)
      expect(json[:plan_product_item][:rate_card_code]).to eq(rate_card.code)
      expect(json[:plan_product_item][:rate_phases_count]).to eq(1)
    end

    context "when the plan does not exist" do
      let(:create_params) { {plan_id: SecureRandom.uuid, rate_card_code: rate_card.code} }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("plan")
      end
    end

    context "when the rate card does not exist" do
      let(:create_params) { {plan_id: plan.id, rate_card_code: "unknown"} }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card")
      end
    end
  end

  describe "GET /api/v2/plan_product_items" do
    subject { get_with_token(organization, "/api/v2/plan_product_items?plan_id=#{plan.id}") }

    let!(:plan_product_item) { create(:plan_product_item, organization:, plan:) }

    before { create(:plan_product_item, organization:) }

    include_examples "requires API permission", "plan_product_item", "read"

    it "returns the plan's product items" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan_product_items].map { |i| i[:lago_id] }).to eq([plan_product_item.id])
    end
  end

  describe "GET /api/v2/plan_product_items/:id" do
    subject { get_with_token(organization, "/api/v2/plan_product_items/#{plan_product_item.id}") }

    let(:plan_product_item) { create(:plan_product_item, organization:, plan:) }

    include_examples "requires API permission", "plan_product_item", "read"

    it "returns the plan product item" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan_product_item][:lago_id]).to eq(plan_product_item.id)
    end

    context "when it does not exist" do
      subject { get_with_token(organization, "/api/v2/plan_product_items/#{SecureRandom.uuid}") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("plan_product_item")
      end
    end
  end
end
