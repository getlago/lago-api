# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::ApproveService do
  subject(:approve_service) { described_class.new(quote_version:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:quote) { create(:quote, organization:) }
  let(:quote_version) { create(:quote_version, quote:, organization:) }

  describe ".call" do
    let(:result) { approve_service.call }

    context "when the quote version is approvable", :premium do
      it "approves the quote version" do
        freeze_time do
          expect(result).to be_success
          expect(result.quote_version.approved?).to eq(true)
          expect(result.quote_version.approved_at).to eq(Time.current)
        end
      end
    end

    context "when the quote version is voided", :premium do
      let(:quote_version) { create(:quote_version, :voided, quote:, organization:) }

      it "does not approve the quote version" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("inappropriate_state")

        quote_version.reload
        expect(quote_version.approved?).to eq(false)
        expect(quote_version.approved_at).to eq(nil)
      end
    end

    context "when the quote version is already approved", :premium do
      let(:quote_version) { create(:quote_version, :approved, quote:, organization:) }

      it "does not approve the quote version" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("inappropriate_state")
      end
    end

    context "when quote version does not exist", :premium do
      let(:quote_version) { nil }

      it "returns a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("quote_version_not_found")
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
