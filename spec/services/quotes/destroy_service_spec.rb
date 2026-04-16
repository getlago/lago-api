# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::DestroyService do
  subject(:destroy_service) { described_class.new(quote:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:quote) { create(:quote, organization:) }

  describe ".call" do
    let(:result) { destroy_service.call }

    context "when quote exists", :premium do
      before { quote }

      it "destroys the quote" do
        expect { result }.to change(Quote, :count).by(-1)
        expect(result).to be_success
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
