# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::AddOns::UpdateService do
  subject(:service) { described_class.new(quote:, id:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:item_id) { "qta_existing" }
  let(:quote) do
    create(:quote, organization:, customer:, order_type: :one_off,
      billing_items: {
        "add_ons" => [{"id" => item_id, "add_on_id" => add_on.id, "name" => "Original", "amount_cents" => 1000}]
      })
  end

  describe "#call" do
    let(:result) { service.call }
    let(:id) { item_id }

    context "with valid params" do
      let(:params) { {name: "Updated Name", amount_cents: 2000} }

      it "updates the add_on fields and returns the quote" do
        expect(result).to be_success
        expect(result.quote.billing_items["add_ons"].first["name"]).to eq("Updated Name")
        expect(result.quote.billing_items["add_ons"].first["amount_cents"]).to eq(2000)
      end

      it "preserves the existing id" do
        expect(result.quote.billing_items["add_ons"].first["id"]).to eq(item_id)
      end
    end

    context "when quote is not draft" do
      let(:params) { {name: "Updated"} }

      before { quote.update!(status: :voided, voided_at: Time.current, void_reason: :manual) }

      it "returns not_allowed_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "when item id is not found" do
      let(:id) { "qta_nonexistent" }
      let(:params) { {name: "Updated"} }

      it "returns not_found_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("billing_item")
      end
    end

    context "when name is cleared" do
      let(:params) { {name: nil} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("name is required")
      end
    end

    context "when add_on_id is updated to one from another organization" do
      let(:other_add_on) { create(:add_on) }
      let(:params) { {add_on_id: other_add_on.id} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("add_on not found in organization")
      end
    end
  end
end
