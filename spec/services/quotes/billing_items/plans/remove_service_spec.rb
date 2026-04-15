# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::Plans::RemoveService do
  subject(:service) { described_class.new(quote:, id:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:item_id) { "qtp_to_remove" }
  let(:quote) do
    create(:quote, organization:, customer:, order_type: :subscription_creation,
      billing_items: {"plans" => [{"id" => item_id, "plan_id" => plan.id}]})
  end

  describe "#call" do
    let(:result) { service.call }

    context "when item exists" do
      let(:id) { item_id }

      it "removes the plan from billing_items and returns the quote" do
        expect(result).to be_success
        expect(result.quote.billing_items["plans"]).to be_empty
      end

      it "only removes the targeted item when multiple plans exist" do
        other_item = {"id" => "qtp_other", "plan_id" => create(:plan, organization:).id}
        quote.update!(billing_items: {"plans" => [{"id" => item_id, "plan_id" => plan.id}, other_item]})

        expect(result.quote.billing_items["plans"].map { |p| p["id"] }).to eq(["qtp_other"])
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
      let(:id) { "qtp_nonexistent" }

      it "returns not_found_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("billing_item")
      end
    end
  end
end
