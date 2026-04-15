# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::AddOns::RemoveService do
  subject(:service) { described_class.new(quote:, id:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:item_id) { "qta_to_remove" }
  let(:quote) do
    create(:quote, organization:, customer:, order_type: :one_off,
      billing_items: {"add_ons" => [{"id" => item_id, "name" => "Work", "amount_cents" => 1000}]})
  end

  describe "#call" do
    let(:result) { service.call }

    context "when item exists" do
      let(:id) { item_id }

      it "removes the add_on from billing_items and returns the quote" do
        expect(result).to be_success
        expect(result.quote.billing_items["add_ons"]).to be_empty
      end

      it "only removes the targeted item when multiple add_ons exist" do
        other_item = {"id" => "qta_other", "name" => "Other", "amount_cents" => 500}
        quote.update!(billing_items: {"add_ons" => [{"id" => item_id, "name" => "Work", "amount_cents" => 1000}, other_item]})

        expect(result.quote.billing_items["add_ons"].map { |a| a["id"] }).to eq(["qta_other"])
      end
    end

    context "when quote is not draft" do
      let(:id) { item_id }

      before { quote.update!(status: :voided, voided_at: Time.current, void_reason: :manual) }

      it "returns not_allowed_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "when item id is not found" do
      let(:id) { "qta_nonexistent" }

      it "returns not_found_failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("billing_item")
      end
    end
  end
end
