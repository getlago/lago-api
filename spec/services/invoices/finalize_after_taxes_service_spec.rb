# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::FinalizeAfterTaxesService do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:, status: :draft) }
  let(:provider_taxes) { nil }
  let(:service) { described_class.new(invoice:, provider_taxes:) }
  let(:credit) { FactoryBot.create(:credit) }
  let(:credit_service) { Credits::CreditNoteService.new(invoice:) }

  let(:credit_result) do
    BaseService::Result.new.tap do |r|
      r.credits = [credit]
    end
  end

  before do
    allow(SendWebhookJob).to receive(:perform_later)
    allow(Utils::ActivityLog).to receive(:produce)
    allow(License).to receive(:premium?).and_return(true)
    allow(Invoices::GeneratePdfAndNotifyJob).to receive(:perform_later)
    allow(Invoices::Payments::CreateService).to receive(:call_async)
    allow(Utils::SegmentTrack).to receive(:invoice_created)
    allow(Invoices::ComputeAmountsFromFees).to receive(:call)
    allow(Invoices::TransitionToFinalStatusService).to receive(:call)
    allow(Credits::AppliedPrepaidCreditService).to receive(:call)
  end

  describe "#call" do
    context "when invoice is not found" do
      let(:invoice) { nil }

      it "returns not_found_failure" do
        result = service.call
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.error_code).to eq("invoice_not_found")
      end
    end

    context "when invoice is draft" do
      before do
        allow(invoice).to receive(:issuing_date=)
        allow(invoice).to receive(:payment_due_date=)
        allow(Credits::CreditNoteService).to receive(:new).and_return(credit_service)
        allow(Credits::CreditNoteService).to receive(:call).and_return(credit_result)
      end

      it "does not set issuing_date or payment_due_date" do
        service.call
        expect(invoice).not_to have_received(:issuing_date=)
        expect(invoice).not_to have_received(:payment_due_date=)
      end

      it "does not create credit note credit or applied prepaid credit" do
        service.call
        expect(Credits::CreditNoteService).not_to have_received(:new)
        expect(Credits::AppliedPrepaidCreditService).not_to have_received(:call)
      end

      it "does not transition to final status" do
        service.call
        expect(Invoices::TransitionToFinalStatusService).not_to have_received(:call)
      end
    end

    context "when invoice is finalized" do
      let(:invoice) { create(:invoice, customer:, organization:, status: :finalized, total_amount_cents: 100) }

      before do
        allow(invoice).to receive(:issuing_date=)
        allow(invoice).to receive(:payment_due_date=)
      end

      it "sets issuing_date and payment_due_date" do
        service.call
        expect(invoice).to have_received(:issuing_date=)
        expect(invoice).to have_received(:payment_due_date=)
      end

      it "calls ComputeAmountsFromFees" do
        service.call
        expect(Invoices::ComputeAmountsFromFees).to have_received(:call).with(invoice:, provider_taxes:)
      end

      it "transitions to final status" do
        service.call
        expect(Invoices::TransitionToFinalStatusService).to have_received(:call).with(invoice:)
      end

      it "enqueues SendWebhookJob" do
        service.call
        expect(SendWebhookJob).to have_received(:perform_later).with("invoice.created", invoice)
      end

      it "calls ActivityLog.produce" do
        service.call
        expect(Utils::ActivityLog).to have_received(:produce).with(invoice, "invoice.created")
      end

      it "enqueues GeneratePdfAndNotifyJob" do
        service.call
        expect(Invoices::GeneratePdfAndNotifyJob).to have_received(:perform_later).with(invoice:, email: true)
      end

      it "calls Invoices::Payments::CreateService.call_async" do
        service.call
        expect(Invoices::Payments::CreateService).to have_received(:call_async).with(invoice:)
      end

      it "calls Utils::SegmentTrack.invoice_created" do
        service.call
        expect(Utils::SegmentTrack).to have_received(:invoice_created).with(invoice)
      end
    end

    context "when ActiveRecord::RecordInvalid is raised" do
      before do
        allow(invoice).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(invoice))
      end

      it "returns record_validation_failure" do
        result = service.call
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end
    end

    context "when BaseService::FailedResult is raised" do
      let(:error_result) do
        BaseService::Result.new.tap do |result|
          result.fail_with_error!(
            BaseService::FailedResult.new(result, "error")
          )
        end
      end

      before do
        allow(invoice).to receive(:save!).and_raise(error_result.error)
      end

      it "returns the failed result" do
        result = service.call
        expect(result.error).to be_a(BaseService::FailedResult)
      end
    end
  end
end
