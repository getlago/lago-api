# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::DestroyService do
  subject(:destroy_service) { described_class.new(fee:) }

  describe "#call" do
    context "when fee is nil" do
      let(:fee) { nil }

      it "returns a not found failure" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("fee")
      end
    end

    context "when fee is attached to an invoice" do
      let(:fee) { create(:fee) }

      it "returns a not allowed failure" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("invoiced_fee")
      end

      it "does not discard the fee" do
        expect { destroy_service.call }.not_to change { fee.reload.discarded? }
      end
    end

    context "when fee is not attached to an invoice" do
      let(:fee) { create(:fee, invoice: nil) }

      it "discards the fee" do
        expect { destroy_service.call }.to change { fee.reload.discarded? }.from(false).to(true)
      end

      it "returns the fee in the result" do
        result = destroy_service.call

        expect(result).to be_success
        expect(result.fee).to eq(fee)
      end
    end
  end
end
