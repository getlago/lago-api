# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Quotes::BillingItems::AddOnsController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }

  describe "POST /api/v1/quotes/:quote_id/add_ons" do
    subject do
      post_with_token(organization, "/api/v1/quotes/#{quote.id}/add_ons", {add_on: create_params})
    end

    let(:create_params) { {add_on_id: add_on.id, name: "Implementation", amount_cents: 100_000, position: 1} }

    it "adds an add_on and returns the updated quote" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:quote][:billing_items]["add_ons"].length).to eq(1)
      expect(json[:quote][:billing_items]["add_ons"].first["name"]).to eq("Implementation")
      expect(json[:quote][:billing_items]["add_ons"].first["id"]).to start_with("qta_")
    end

    context "when quote does not belong to organization" do
      it "returns not_found_error" do
        post_with_token(organization, "/api/v1/quotes/#{create(:quote).id}/add_ons", {add_on: create_params})
        expect(response).to be_not_found_error("quote")
      end
    end

    context "when order type is subscription_creation" do
      let(:quote) { create(:quote, organization:, customer:, order_type: :subscription_creation) }

      it "returns unprocessable_entity" do
        subject
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when quote is not draft" do
      before { quote.update!(status: :voided, voided_at: Time.current, void_reason: :manual) }

      it "returns method_not_allowed" do
        subject
        expect(response).to have_http_status(:method_not_allowed)
      end
    end
  end

  describe "PUT /api/v1/quotes/:quote_id/add_ons/:id" do
    subject do
      put_with_token(organization, "/api/v1/quotes/#{quote.id}/add_ons/#{item_id}", {add_on: update_params})
    end

    let(:item_id) { "qta_existing" }
    let(:update_params) { {name: "Updated Name", amount_cents: 200_000} }

    before do
      quote.update!(billing_items: {"add_ons" => [{"id" => item_id, "name" => "Original", "amount_cents" => 100_000}]})
    end

    it "updates the add_on and returns the quote" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:quote][:billing_items]["add_ons"].first["name"]).to eq("Updated Name")
    end

    context "when item id is not found" do
      it "returns not_found_error" do
        put_with_token(organization, "/api/v1/quotes/#{quote.id}/add_ons/qta_nonexistent", {add_on: update_params})
        expect(response).to be_not_found_error("billing_item")
      end
    end

    context "when quote is not draft" do
      before { quote.update!(status: :voided, voided_at: Time.current, void_reason: :manual) }

      it "returns method_not_allowed" do
        subject
        expect(response).to have_http_status(:method_not_allowed)
      end
    end
  end

  describe "DELETE /api/v1/quotes/:quote_id/add_ons/:id" do
    subject do
      delete_with_token(organization, "/api/v1/quotes/#{quote.id}/add_ons/#{item_id}")
    end

    let(:item_id) { "qta_to_remove" }

    before do
      quote.update!(billing_items: {"add_ons" => [{"id" => item_id, "name" => "Work", "amount_cents" => 1000}]})
    end

    it "removes the add_on and returns the updated quote" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:quote][:billing_items]["add_ons"]).to be_empty
    end

    context "when item id is not found" do
      it "returns not_found_error" do
        delete_with_token(organization, "/api/v1/quotes/#{quote.id}/add_ons/qta_nonexistent")
        expect(response).to be_not_found_error("billing_item")
      end
    end

    context "when quote is not draft" do
      before { quote.update!(status: :voided, voided_at: Time.current, void_reason: :manual) }

      it "returns method_not_allowed" do
        subject
        expect(response).to have_http_status(:method_not_allowed)
      end
    end
  end
end
