# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::ApproveService do
  subject(:approve_service) { described_class.new(quote:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:quote) { create(:quote, organization:) }

  describe ".call" do
    let(:result) { approve_service.call }

    context "when the quote is approvable", :premium do
      it "approves the quote" do
        freeze_time do
          expect(result).to be_success
          expect(result.quote.approved?).to eq(true)
          expect(result.quote.approved_at).to eq(Time.current)
        end
      end
    end

    context "when the quote is voided", :premium do
      let(:quote) { create(:quote, :voided, organization:) }

      it "does not approve the quote" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("inappropriate_state")

        quote.reload
        expect(quote.approved?).to eq(false)
        expect(quote.approved_at).to eq(nil)
      end
    end

    context "when the quote is already approved", :premium do
      let(:quote) { create(:quote, :approved, organization:) }

      it "does not approve the quote" do
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
