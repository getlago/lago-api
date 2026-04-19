# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::CreateService do
  subject(:create_service) { described_class.new(organization:, customer:, params: create_params) }

  let(:owner) { create(:user) }
  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:create_params) {
    {
      auto_execute: true,
      backdated_billing: nil,
      billing_items: {},
      commercial_terms: {},
      contacts: {},
      content: "Test content",
      currency: "USD",
      description: "Test description",
      execution_mode: nil,
      internal_notes: "Test internal notes",
      legal_text: "Test legal text",
      metadata: {},
      order_type: :subscription_creation,
      owners: [owner.id]
    }
  }

  describe ".call" do
    let(:result) { create_service.call }

    context "when license is premium", :premium do
      it "creates an empty draft quote" do
        travel_to(DateTime.new(2025, 3, 11, 20, 0, 0)) do
          expect(result).to be_success
          expect(result.quote.organization.id).to eq(organization.id)
          expect(result.quote.customer.id).to eq(customer.id)
          expect(result.quote.version).to eq(1)
          expect(result.quote.sequential_id).to eq(1)
          expect(result.quote.number).to eq("QT-2025-0001")
          expect(result.quote.draft?).to eq(true)
          expect(result.quote.auto_execute).to eq(true)
          expect(result.quote.backdated_billing).to eq(nil)
          expect(result.quote.billing_items).to eq(
            "plans" => [],
            "coupons" => [],
            "wallet_credits" => []
          )
          expect(result.quote.commercial_terms).to eq({})
          expect(result.quote.contacts).to eq({})
          expect(result.quote.content).to eq("Test content")
          expect(result.quote.currency).to eq("USD")
          expect(result.quote.description).to eq("Test description")
          expect(result.quote.execution_mode).to eq(nil)
          expect(result.quote.internal_notes).to eq("Test internal notes")
          expect(result.quote.legal_text).to eq("Test legal text")
          expect(result.quote.metadata).to eq({})
          expect(result.quote.order_type).to eq("subscription_creation")
          expect(result.quote.owner_ids).to eq([owner.id])
        end
      end
    end

    context "when organization does not exist", :premium do
      let(:organization) { nil }
      let(:customer) { create(:customer) }

      it "returns a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("organization_not_found")
      end
    end

    context "when customer does not exist", :premium do
      let(:customer) { nil }

      it "returns a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("customer_not_found")
      end
    end

    context "when license is not premium" do
      it "returns forbidden status" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end
    end
  end
end
