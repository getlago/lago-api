# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Quotes::BillingItems::PlansController, :premium do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type: :subscription_creation) }

  describe "POST /api/v1/quotes/:quote_id/plans" do
    subject do
      post_with_token(organization, "/api/v1/quotes/#{quote.id}/plans", {plan: create_params})
    end

    let(:create_params) { {plan_id: plan.id, plan_name: "Enterprise", position: 1} }

    it "adds a plan and returns the updated quote" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:quote][:lago_id]).to eq(quote.id)
      expect(json[:quote][:billing_items][:plans].length).to eq(1)
      expect(json[:quote][:billing_items][:plans].first[:plan_id]).to eq(plan.id)
      expect(json[:quote][:billing_items][:plans].first[:id]).to start_with("qtp_")
    end

    context "when quote does not belong to organization" do
      let(:other_quote) { create(:quote) }

      it "returns not_found_error" do
        post_with_token(organization, "/api/v1/quotes/#{other_quote.id}/plans", {plan: create_params})
        expect(response).to be_not_found_error("quote")
      end
    end

    context "when quote is not draft" do
      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns method_not_allowed" do
        subject
        expect(response).to have_http_status(:method_not_allowed)
      end
    end

    context "when plan does not belong to organization" do
      let(:create_params) { {plan_id: create(:plan).id, plan_name: "Other"} }

      it "returns unprocessable_entity" do
        subject
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PUT /api/v1/quotes/:quote_id/plans/:id" do
    subject do
      put_with_token(organization, "/api/v1/quotes/#{quote.id}/plans/#{item_id}", {plan: update_params})
    end

    let(:item_id) { "qtp_existing" }
    let(:update_params) { {plan_name: "Updated Name"} }

    before do
      quote.update!(billing_items: {"plans" => [{"id" => item_id, "plan_id" => plan.id, "plan_name" => "Original"}]})
    end

    it "updates the plan and returns the quote" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:quote][:billing_items][:plans].first[:plan_name]).to eq("Updated Name")
      expect(json[:quote][:billing_items][:plans].first[:id]).to eq(item_id)
    end

    context "when item id is not found" do
      it "returns not_found_error" do
        put_with_token(organization, "/api/v1/quotes/#{quote.id}/plans/qtp_nonexistent", {plan: update_params})
        expect(response).to be_not_found_error("billing_item")
      end
    end

    context "when quote is not draft" do
      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns method_not_allowed" do
        subject
        expect(response).to have_http_status(:method_not_allowed)
      end
    end
  end

  describe "DELETE /api/v1/quotes/:quote_id/plans/:id" do
    subject do
      delete_with_token(organization, "/api/v1/quotes/#{quote.id}/plans/#{item_id}")
    end

    let(:item_id) { "qtp_to_remove" }

    before do
      quote.update!(billing_items: {"plans" => [{"id" => item_id, "plan_id" => plan.id}]})
    end

    it "removes the plan and returns the updated quote" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:quote][:billing_items][:plans]).to be_empty
    end

    context "when item id is not found" do
      it "returns not_found_error" do
        delete_with_token(organization, "/api/v1/quotes/#{quote.id}/plans/qtp_nonexistent")
        expect(response).to be_not_found_error("billing_item")
      end
    end

    context "when quote is not draft" do
      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns method_not_allowed" do
        subject
        expect(response).to have_http_status(:method_not_allowed)
      end
    end
  end
end
