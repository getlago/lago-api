# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::CreatePayInAdvanceChargeJob do
  let(:charge) { create(:standard_charge, :pay_in_advance, invoiceable: true) }
  let(:event) { create(:event) }
  let(:timestamp) { Time.current.to_i }

  let(:invoice) { nil }
  let(:result) { BaseService::Result.new }

  before do
    allow(Invoices::CreatePayInAdvanceChargeService).to receive(:call)
      .with(charge:, event:, timestamp:)
      .and_return(result)
  end

  it "calls the create pay in advance charge service" do
    described_class.perform_now(charge:, event:, timestamp:)

    expect(Invoices::CreatePayInAdvanceChargeService).to have_received(:call)
  end

  context "when result is a failure" do
    let(:result) do
      BaseService::Result.new.single_validation_failure!(error_code: "error")
    end

    it "raises an error" do
      expect do
        described_class.perform_now(charge:, event:, timestamp:)
      end.to raise_error(BaseService::FailedResult)

      expect(Invoices::CreatePayInAdvanceChargeService).to have_received(:call)
    end

    context "with a previously created invoice" do
      let(:invoice) { create(:invoice, :generating) }

      it "raises an error" do
        expect do
          described_class.perform_now(charge:, event:, timestamp:, invoice:)
        end.to raise_error(BaseService::FailedResult)

        expect(Invoices::CreatePayInAdvanceChargeService).to have_received(:call)
      end
    end

    context "when no invoice is attached to the result" do
      let(:result_invoice) { create(:invoice, :draft) }

      before { result.invoice = nil }

      it "raises an error" do
        expect do
          described_class.perform_now(charge:, event:, timestamp:)
        end.to raise_error(BaseService::FailedResult)

        expect(Invoices::CreatePayInAdvanceChargeService).to have_received(:call)
      end
    end
  end
end
