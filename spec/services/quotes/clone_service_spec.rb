# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::CloneService do
  subject(:clone_service) { described_class.new(quote:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:owner) { create(:user) }
  let(:quote) { create(:quote, organization:) }

  describe ".call" do
    let(:result) { clone_service.call }

    context "when the quote is clonable", :premium do
      before do
        quote.quote_owners.create!(
          organization_id: quote.organization_id,
          user_id: owner.id
        )
      end

      it "creates an clone and voids the original quote" do
        expect(result).to be_success
        cloned = result.quote
        expect(cloned.id).not_to eq(quote.id)
        expect(cloned.organization.id).to eq(quote.organization.id)
        expect(cloned.customer.id).to eq(quote.customer.id)
        expect(cloned.sequential_id).to eq(quote.sequential_id)
        expect(cloned.version).to eq(quote.version + 1)
        expect(cloned.number).to eq(quote.number)
        expect(cloned.draft?).to eq(true)
        expect(cloned.owner_ids).to eq([owner.id])

        quote.reload
        expect(quote.voided?).to eq(true)
        expect(quote.void_reason).to eq("superseded")
      end
    end

    context "when the quote is not clonable", :premium do
      let(:quote) { create(:quote, :approved, organization:) }

      it "does not create a clone" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("inappropriate_state")

        quote.reload
        expect(quote.approved?).to eq(true)
        expect(quote.void_reason).to eq(nil)
        expect(quote.voided_at).to eq(nil)
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
