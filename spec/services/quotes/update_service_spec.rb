# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::UpdateService do
  subject(:update_service) { described_class.new(quote:, params: update_params) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:owner) { create(:user) }
  let(:quote) { create(:quote, organization:) }
  let(:update_params) {
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
    let(:result) { update_service.call }

    context "when draft quote", :premium do
      it "updates the quote" do
        expect(result).to be_success
        expect(result.quote.id).to eq(quote.id)
        expect(result.quote.organization_id).to eq(quote.organization_id)
        expect(result.quote.customer_id).to eq(quote.customer_id)
        expect(result.quote.version).to eq(quote.version)
        expect(result.quote.sequential_id).to eq(quote.sequential_id)
        expect(result.quote.number).to eq(quote.number)
        expect(result.quote.draft?).to eq(true)

        expect(result.quote.auto_execute).to eq(true)
        expect(result.quote.backdated_billing).to eq(nil)
        expect(result.quote.billing_items).to eq({})
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

    context "when approved quote", :premium do
      let(:quote) { create(:quote, :approved, organization:) }

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("inappropriate_state")
      end
    end

    context "when voided quote", :premium do
      let(:quote) { create(:quote, :voided, organization:) }

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("inappropriate_state")
      end
    end

    context "when quote does not exist", :premium do
      let(:quote) { nil }

      it "returns a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("quote_not_found")
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
