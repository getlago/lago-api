# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::Plans::UpdateService, :premium do
  subject(:service) { described_class.new(quote:, id:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:item_id) { "qtp_existing" }
  let(:quote) do
    create(:quote, organization:, customer:, order_type: :subscription_creation,
      billing_items: {"plans" => [{"id" => item_id, "plan_id" => plan.id, "plan_name" => "Original"}]})
  end

  describe "#call" do
    let(:result) { service.call }
    let(:id) { item_id }

    context "with valid params" do
      let(:params) { {plan_name: "Updated Name"} }

      it "updates the plan fields and returns the quote" do
        expect(result).to be_success
        expect(result.quote.billing_items["plans"].first["plan_name"]).to eq("Updated Name")
      end

      it "preserves the existing id" do
        expect(result.quote.billing_items["plans"].first["id"]).to eq(item_id)
      end

      it "preserves fields not included in params" do
        expect(result.quote.billing_items["plans"].first["plan_id"]).to eq(plan.id)
      end
    end

    context "when quote is nil" do
      let(:id) { item_id }
      let(:params) { {plan_name: "Updated"} }

      it "returns not_found_failure" do
        result = described_class.new(quote: nil, id:, params:).call
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("quote")
      end
    end

    context "when quote is not draft" do
      let(:params) { {plan_name: "Updated"} }

      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns not_allowed_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "when item id is not found" do
      let(:id) { "qtp_nonexistent" }
      let(:params) { {plan_name: "Updated"} }

      it "returns not_found_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("billing_item")
      end
    end

    context "when updated plan_id does not belong to organization" do
      let(:other_plan) { create(:plan) }
      let(:params) { {plan_id: other_plan.id} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("plan not found in organization")
      end
    end

    context "when plan_id is cleared" do
      let(:params) { {plan_id: nil} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("plan_id is required")
      end
    end
  end
end
