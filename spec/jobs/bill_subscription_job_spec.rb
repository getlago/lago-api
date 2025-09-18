# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillSubscriptionJob do
  let(:subscriptions) { [create(:subscription)] }
  let(:timestamp) { Time.zone.now.to_i }

  let(:invoice) { nil }
  let(:invoicing_reason) { :subscription_starting }
  let(:result) { BaseService::Result.new }

  before do
    allow(Invoices::SubscriptionService).to receive(:call)
      .with(subscriptions:, timestamp:, invoicing_reason:, invoice:, skip_charges: false)
      .and_return(result)
  end

  it "calls the invoices create service" do
    described_class.perform_now(subscriptions, timestamp, invoicing_reason:)

    expect(Invoices::SubscriptionService).to have_received(:call)
  end

  context "when result is a failure" do
    let(:result) do
      result = BaseService::Result.new
      result.invoice = invoice
      result.single_validation_failure!(error_code: "error")
    end

    it "raises an error" do
      expect do
        described_class.perform_now(subscriptions, timestamp, invoicing_reason:)
      end.to raise_error(BaseService::FailedResult)

      expect(Invoices::SubscriptionService).to have_received(:call)
    end

    context "with a previously created invoice" do
      let(:invoice) { create(:invoice, :generating) }

      it "raises an error" do
        expect do
          described_class.perform_now(subscriptions, timestamp, invoicing_reason:, invoice:)
        end.to raise_error(BaseService::FailedResult)

        expect(Invoices::SubscriptionService).to have_received(:call)
      end

      it "creates an ErrorDetail" do
        expect do
          described_class.perform_now(subscriptions, timestamp, invoicing_reason:, invoice:)
        end.to raise_error(BaseService::FailedResult).and change(invoice.error_details.invoice_generation_error, :count)
          .from(0).to(1)
      end
    end

    context "when a generating invoice is attached to the result" do
      let(:result_invoice) { create(:invoice, :generating) }

      before { result.invoice = result_invoice }

      it "retries the job with the invoice" do
        described_class.perform_now(subscriptions, timestamp, invoicing_reason:)

        expect(Invoices::SubscriptionService).to have_received(:call)

        expect(described_class).to have_been_enqueued
          .with(subscriptions, timestamp, invoicing_reason:, invoice: result_invoice, skip_charges: false)
      end
    end

    context "when a not generating invoice is attached to the result" do
      let(:result_invoice) { create(:invoice, :draft) }

      before { result.invoice = result_invoice }

      it "raises an error" do
        expect do
          described_class.perform_now(subscriptions, timestamp, invoicing_reason:)
        end.to raise_error(BaseService::FailedResult)

        expect(Invoices::SubscriptionService).to have_received(:call)
      end

      it "creates an invoice generation error_detail" do
        expect do
          described_class.perform_now(subscriptions, timestamp, invoicing_reason:)
        end.to raise_error(BaseService::FailedResult)

        expect(ErrorDetail.invoice_generation_error.size).to eq(1)
        expect(result_invoice.error_details.invoice_generation_error.count).to eq(1)
      end
    end
  end
end
