# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::VoidService do
  subject(:result) { described_class.call(quote:, reason:) }

  let(:organization) { create(:organization, feature_flags: ["quote"]) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:, status: :draft) }
  let(:reason) { :manual }

  context "when license is premium", :premium do
    it "voids a draft quote" do
      freeze_time do
        expect(result).to be_success

        quote.reload
        expect(quote.status).to eq("voided")
        expect(quote.void_reason).to eq("manual")
        expect(quote.voided_at).to eq(Time.current)
        expect(result.quote).to eq(quote)
      end
    end

    context "when the quote is approved" do
      let(:quote) { create(:quote, organization:, customer:, status: :approved) }

      it "voids the quote" do
        expect(result).to be_success

        quote.reload
        expect(quote.status).to eq("voided")
        expect(quote.void_reason).to eq("manual")
        expect(quote.voided_at).not_to be_nil
      end
    end

    context "when the quote has owners" do
      let(:owner) { create(:user) }

      before { create(:quote_owner, quote:, organization:, user: owner) }

      it "does not drop the owners" do
        expect(result).to be_success
        expect(quote.reload.owners).to contain_exactly(owner)
      end
    end

    context "when the quote is already voided" do
      let(:quote) do
        create(
          :quote,
          organization:,
          customer:,
          status: :voided,
          void_reason: "superseded",
          voided_at: 1.day.ago
        )
      end

      it "returns an inappropriate_state failure without mutating the quote" do
        original_voided_at = quote.voided_at
        original_void_reason = quote.void_reason

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("inappropriate_state")

        quote.reload
        expect(quote.void_reason).to eq(original_void_reason)
        expect(quote.voided_at.to_i).to eq(original_voided_at.to_i)
      end
    end

    %i[manual superseded cascade_of_expired cascade_of_voided].each do |valid_reason|
      context "with reason #{valid_reason.inspect}" do
        let(:reason) { valid_reason }

        it "voids the quote" do
          expect(result).to be_success
          expect(result.quote.void_reason).to eq(valid_reason.to_s)
        end
      end
    end

    context "when the reason is passed as a String" do
      let(:reason) { "manual" }

      it "voids the quote" do
        expect(result).to be_success
        expect(result.quote.void_reason).to eq("manual")
      end
    end

    context "when the reason is unknown" do
      let(:reason) { :foo }

      it "returns a single validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:reason]).to eq(["invalid_void_reason"])
      end
    end

    context "when the reason is an Integer" do
      let(:reason) { 42 }

      it "does not raise and returns a validation failure" do
        expect { result }.not_to raise_error
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:reason]).to eq(["invalid_void_reason"])
      end
    end

    context "when the reason is nil" do
      let(:reason) { nil }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:reason]).to eq(["invalid_void_reason"])
      end
    end

    context "when the reason is blank" do
      let(:reason) { "" }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:reason]).to eq(["invalid_void_reason"])
      end
    end

    context "when quote is nil" do
      let(:quote) { nil }

      it "returns a not_found failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("quote")
      end
    end

    context "when the quote feature flag is disabled" do
      let(:organization) { create(:organization) }

      it "returns a forbidden failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
      end
    end
  end

  context "when license is not premium" do
    it "returns a forbidden failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end
  end
end
