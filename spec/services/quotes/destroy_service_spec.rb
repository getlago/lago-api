# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::DestroyService do
  subject(:destroy_service) { described_class.new(quote:) }

  let(:quote) { create(:quote, status: :draft) }

  describe ".call" do
    let(:result) { destroy_service.call }

    context "when quote exists", :premium do
      before { quote }

      it "destroys the quote" do
        expect { result }.to change(Quote, :count).by(-1)
        expect(result).to be_success
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
