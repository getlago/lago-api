# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::Plans::AddService do
  subject(:service) { described_class.new(quote:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type: :subscription_creation) }

  describe "#call" do
    let(:result) { service.call }

    context "with valid params" do
      let(:params) { {plan_id: plan.id, plan_name: "Enterprise", position: 1} }

      it "appends the plan to billing_items and returns the quote" do
        expect(result).to be_success
        expect(result.quote.billing_items["plans"].length).to eq(1)
        expect(result.quote.billing_items["plans"].first["plan_id"]).to eq(plan.id)
      end

      it "generates a stable id with qtp_ prefix" do
        expect(result.quote.billing_items["plans"].first["id"]).to start_with("qtp_")
      end

      it "preserves an existing id" do
        params[:id] = "qtp_existing"
        expect(result.quote.billing_items["plans"].first["id"]).to eq("qtp_existing")
      end

      it "appends to existing plans without replacing them" do
        existing_item = {"id" => "qtp_first", "plan_id" => create(:plan, organization:).id}
        quote.update!(billing_items: {"plans" => [existing_item]})

        expect(result.quote.billing_items["plans"].length).to eq(2)
      end
    end

    context "when quote is not draft" do
      let(:params) { {plan_id: plan.id} }

      before { quote.update!(status: :approved, approved_at: Time.current) }

      it "returns not_allowed_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "when order type is one_off" do
      let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }
      let(:params) { {plan_id: plan.id} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:billing_item]).to include("plans not allowed for one_off order type")
      end
    end

    context "when plan_id is missing" do
      let(:params) { {plan_name: "Enterprise"} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("plan_id is required")
      end
    end

    context "when plan does not belong to organization" do
      let(:other_plan) { create(:plan) }
      let(:params) { {plan_id: other_plan.id, plan_name: "Other"} }

      it "returns validation_failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_item]).to include("plan not found in organization")
      end
    end
  end
end
