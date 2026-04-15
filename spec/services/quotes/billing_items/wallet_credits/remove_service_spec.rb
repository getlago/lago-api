# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::WalletCredits::RemoveService do
  subject(:service) { described_class.new(quote:, id:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:item_id) { "qtw_to_remove" }
  let(:quote) do
    create(:quote, organization:, customer:, order_type: :subscription_creation,
      billing_items: {
        "wallet_credits" => [{"id" => item_id, "name" => "Credits", "currency" => "EUR"}]
      })
  end

  describe "#call" do
    let(:result) { service.call }

    context "when item exists" do
      let(:id) { item_id }

      it "removes the wallet credit from billing_items and returns the quote" do
        expect(result).to be_success
        expect(result.quote.billing_items["wallet_credits"]).to be_empty
      end

      it "only removes the targeted item when multiple wallet credits exist" do
        other_item = {"id" => "qtw_other", "name" => "Other Credits", "currency" => "EUR"}
        quote.update!(billing_items: {
          "wallet_credits" => [
            {"id" => item_id, "name" => "Credits", "currency" => "EUR"},
            other_item
          ]
        })

        expect(result.quote.billing_items["wallet_credits"].map { |w| w["id"] }).to eq(["qtw_other"])
      end
    end

    context "when quote is not draft" do
      let(:id) { item_id }

      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns not_allowed_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "when item id is not found" do
      let(:id) { "qtw_nonexistent" }

      it "returns not_found_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("billing_item")
      end
    end
  end
end
