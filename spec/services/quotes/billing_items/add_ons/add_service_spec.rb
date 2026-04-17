# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::AddOns::AddService do
  subject(:service) { described_class.new(quote:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }

  describe "#call" do
    let(:result) { service.call }

    context "with catalog add_on reference" do
      let(:params) { {add_on_id: add_on.id, name: "Implementation", amount_cents: 100_000, position: 1} }

      it "appends the add_on and returns the quote" do
        expect(result).to be_success
        expect(result.quote.billing_items["add_ons"].length).to eq(1)
        expect(result.quote.billing_items["add_ons"].first["add_on_id"]).to eq(add_on.id)
      end

      it "generates a stable id with qta_ prefix" do
        expect(result.quote.billing_items["add_ons"].first["id"]).to start_with("qta_")
      end
    end

    context "with custom add_on (no catalog reference)" do
      let(:params) { {name: "Custom Work", amount_cents: 50_000, position: 1} }

      it "returns success and generates id" do
        expect(result).to be_success
        expect(result.quote.billing_items["add_ons"].first["id"]).to start_with("qta_")
      end
    end

    context "when quote is nil" do
      let(:params) { {name: "Work", amount_cents: 1000} }

      it "returns not_found_failure" do
        result = described_class.new(quote: nil, params:).call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("quote")
      end
    end

    context "when quote is not draft" do
      let(:params) { {name: "Work", amount_cents: 1000} }

      before { quote.update!(status: :voided, voided_at: Time.current, void_reason: :manual) }

      it "returns not_allowed_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "when order type is subscription_creation" do
      let(:quote) { create(:quote, organization:, customer:, order_type: :subscription_creation) }
      let(:params) { {name: "Work", amount_cents: 1000} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("add_ons not allowed for subscription order type")
      end
    end

    context "when name is missing" do
      let(:params) { {amount_cents: 1000} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("name is required")
      end
    end

    context "when add_on_id is absent and amount_cents is missing" do
      let(:params) { {name: "Custom Work"} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("amount_cents is required when add_on_id is not provided")
      end
    end

    context "when add_on does not belong to organization" do
      let(:other_add_on) { create(:add_on) }
      let(:params) { {add_on_id: other_add_on.id, name: "Work", amount_cents: 1000} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("add_on not found in organization")
      end
    end
  end
end
