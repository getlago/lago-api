# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Quotes::BillingItems::WalletCreditsController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type: :subscription_creation) }

  describe "POST /api/v1/quotes/:quote_id/wallet_credits" do
    subject do
      post_with_token(organization, "/api/v1/quotes/#{quote.id}/wallet_credits", {wallet_credit: create_params})
    end

    let(:create_params) do
      {
        name: "Monthly credits",
        currency: "EUR",
        rate_amount: "1.0",
        paid_credits: "500.0",
        granted_credits: "500.0",
        position: 1
      }
    end

    it "adds a wallet credit and returns the updated quote" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:quote][:billing_items]["wallet_credits"].length).to eq(1)
      expect(json[:quote][:billing_items]["wallet_credits"].first["name"]).to eq("Monthly credits")
      expect(json[:quote][:billing_items]["wallet_credits"].first["id"]).to start_with("qtw_")
    end

    context "when quote does not belong to organization" do
      it "returns not_found_error" do
        post_with_token(organization, "/api/v1/quotes/#{create(:quote).id}/wallet_credits", {wallet_credit: create_params})
        expect(response).to be_not_found_error("quote")
      end
    end

    context "when order type is one_off" do
      let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }

      it "returns unprocessable_entity" do
        subject
        expect(response).to have_http_status(:unprocessable_entity)
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

  describe "PUT /api/v1/quotes/:quote_id/wallet_credits/:id" do
    subject do
      put_with_token(organization, "/api/v1/quotes/#{quote.id}/wallet_credits/#{item_id}", {wallet_credit: update_params})
    end

    let(:item_id) { "qtw_existing" }
    let(:update_params) { {paid_credits: "1000.0"} }

    before do
      quote.update!(billing_items: {
        "wallet_credits" => [{"id" => item_id, "name" => "Credits", "currency" => "EUR", "paid_credits" => "500.0"}]
      })
    end

    it "updates the wallet credit and returns the quote" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:quote][:billing_items]["wallet_credits"].first["paid_credits"]).to eq("1000.0")
    end

    context "when item id is not found" do
      it "returns not_found_error" do
        put_with_token(organization, "/api/v1/quotes/#{quote.id}/wallet_credits/qtw_nonexistent", {wallet_credit: update_params})
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

  describe "DELETE /api/v1/quotes/:quote_id/wallet_credits/:id" do
    subject do
      delete_with_token(organization, "/api/v1/quotes/#{quote.id}/wallet_credits/#{item_id}")
    end

    let(:item_id) { "qtw_to_remove" }

    before do
      quote.update!(billing_items: {
        "wallet_credits" => [{"id" => item_id, "name" => "Credits", "currency" => "EUR"}]
      })
    end

    it "removes the wallet credit and returns the updated quote" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:quote][:billing_items]["wallet_credits"]).to be_empty
    end

    context "when item id is not found" do
      it "returns not_found_error" do
        delete_with_token(organization, "/api/v1/quotes/#{quote.id}/wallet_credits/qtw_nonexistent")
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
