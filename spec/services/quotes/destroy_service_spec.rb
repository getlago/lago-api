# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::DestroyService do
  subject(:destroy_service) { described_class.new(quote:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, :subscription_creation, customer:, organization:, version: 1) }

  describe "#call" do
    it "destroys the quote" do
      quote # ensure created

      expect { destroy_service.call }.to change(Quote, :count).by(-1)
    end

    it "returns the destroyed quote" do
      result = destroy_service.call

      expect(result).to be_success
      expect(result.quote).to eq(quote)
    end

    context "when quote is nil" do
      let(:quote) { nil }

      it "returns not found failure" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("quote")
      end
    end

    context "when quote is approved" do
      let(:quote) { create(:quote, :subscription_creation, :approved, customer:, organization:, version: 1) }

      it "returns not allowed failure" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("quote_not_draft")
      end
    end

    context "when quote is voided" do
      let(:quote) { create(:quote, :subscription_creation, :voided, customer:, organization:, version: 1) }

      it "returns not allowed failure" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("quote_not_draft")
      end
    end

    context "when quote version is greater than 1" do
      let(:quote) { create(:quote, :subscription_creation, customer:, organization:, version: 2) }

      it "returns not allowed failure" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("quote_not_deletable")
      end
    end
  end
end
