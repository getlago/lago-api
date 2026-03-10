# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::CreateService do
  subject(:create_service) {
    described_class.new(
      organization:,
      quote:,
      params: create_params
    )
  }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:create_params) {
    {
      billing_items: {},
      content: "Test content"
    }
  }

  describe ".call" do
    let(:result) { create_service.call }

    context "when license is premium", :premium do
      it "creates draft quote version" do
        expect(result).to be_success
        expect(result.quote_version.quote_id).to eq(quote.id)
        expect(result.quote_version.organization_id).to eq(quote.organization_id)
        expect(result.quote_version.version).to eq(1)
        expect(result.quote_version.draft?).to eq(true)
        expect(result.quote_version.content).to eq("Test content")
        expect(result.quote_version.share_token).not_to be_nil
        expect(result.quote_version.billing_items).to eq({})
      end
    end

    context "when organization does not exist", :premium do
      let(:organization) { nil }
      let(:customer) { create(:customer) }
      let(:quote) { create(:quote) }

      it "returns a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("organization_not_found")
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
