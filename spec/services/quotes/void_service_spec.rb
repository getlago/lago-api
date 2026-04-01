# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::VoidService do
  subject(:void_service) { described_class.new(quote:, reason:) }

  let(:quote) { create(:quote, status: :draft) }
  let(:reason) { "manual" }

  describe ".call" do
    let(:result) { void_service.call }

    context "when quote is voidable", :premium do
      let(:current_time) { DateTime.new(2025, 3, 11, 20, 0, 0) }

      it "voides the quote" do
        travel_to(current_time) do
          expect(result).to be_success
          expect(result.quote.voided?).to eq(true)
          expect(result.quote.void_reason).to eq(reason)
          expect(result.quote.voided_at).to eq(current_time)
          expect(result.quote.share_token).to eq(nil)
        end
      end
    end

    context "when quote isn't voidable", :premium do
      before do
        quote.update!(status: :voided, void_reason: :manual, voided_at: Time.current)
      end

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:quote]).to eq(["inappropriate_state"])
      end
    end

    context "when reason is invalid", :premium do
      context "when reason is blank" do
        let(:reason) { nil }

        it "returns validation failure" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:quote]).to eq(["invalid_void_reason"])
        end
      end

      context "when reason is undefined" do
        let(:reason) { "invalid_reason" }

        it "returns validation failure" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:quote]).to eq(["invalid_void_reason"])
        end
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
