# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::ApproveService do
  subject(:approve_service) { described_class.new(quote:) }

  let(:quote) { create(:quote, status: :draft) }

  describe ".call" do
    let(:result) { approve_service.call }

    context "when the quote is approvable", :premium do
      let(:current_time) { DateTime.new(2025, 3, 11, 20, 0, 0) }

      it "approves the quote" do
        travel_to(current_time) do
          expect(result).to be_success
          expect(result.quote.approved?).to eq(true)
          expect(result.quote.approved_at).to eq(current_time)
        end
      end
    end

    context "when the quote is voided", :premium do
      before do
        quote.update!(status: :voided, void_reason: :manual, voided_at: Time.current)
      end

      it "does not approve the quote" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:quote]).to eq(["inappropriate_state"])

        quote.reload
        expect(quote.approved?).to eq(false)
        expect(quote.approved_at).to eq(nil)
      end
    end

    context "when the quote is already approved", :premium do
      before do
        quote.update!(status: :approved, approved_at: Time.current)
      end

      it "does not approve the quote" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:quote]).to eq(["inappropriate_state"])
      end
    end

    context "when quote does not exist", :premium do
      let(:quote) { nil }

      it "returns a not found error" do
        expect(result).not_to be_success
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
