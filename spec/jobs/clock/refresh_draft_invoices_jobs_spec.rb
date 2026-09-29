# frozen_string_literal: true

require "rails_helper"

describe Clock::RefreshDraftInvoicesJob, job: true do
  subject { described_class }

  describe ".perform" do
    let(:invoice) { create(:invoice, :draft) }
    let(:subscription) { create(:subscription) }
    let(:invoice_subscription) { create(:invoice_subscription, invoice:, subscription:) }

    before do
      invoice_subscription
      allow(Invoices::RefreshDraftService).to receive(:call)
    end

    context "when not ready to be refreshed" do
      it "does not call the refresh service" do
        described_class.perform_now
        expect(Invoices::RefreshDraftJob).not_to have_been_enqueued.with(invoice:)
      end
    end

    context "when invoice is related only to terminated subscriptions" do
      let(:invoice) { create(:invoice, :draft, ready_to_be_refreshed: true) }
      let(:subscription) { create(:subscription, :terminated) }

      it "does not call the refresh service" do
        described_class.perform_now
        expect(Invoices::RefreshDraftJob).not_to have_been_enqueued.with(invoice:)
      end
    end

    context "when ready to be refreshed" do
      let(:invoice) { create(:invoice, :draft, ready_to_be_refreshed: true) }

      it "calls the refresh service" do
        described_class.perform_now
        expect(Invoices::RefreshDraftJob).to have_been_enqueued.with(invoice:)
      end
    end

    context "when a product catalog invoice is ready to be refreshed" do
      let(:invoice) do
        create(
          :invoice,
          :draft,
          customer:,
          organization: customer.organization,
          ready_to_be_refreshed: true
        )
      end
      let(:customer) { create(:customer) }
      let(:invoice_subscription) { nil }
      let(:contract) { create(:contract, organization: customer.organization, customer:) }
      let(:billing_segment) do
        create(
          :billing_segment,
          organization: customer.organization,
          customer:,
          contract:,
          invoice:,
          status: :done
        )
      end

      before { billing_segment }

      it "enqueues its refresh job without a legacy subscription" do
        described_class.perform_now

        expect(Invoices::RefreshDraftJob).to have_been_enqueued.with(invoice:)
      end

      context "when the contract is terminated" do
        let(:contract) { create(:contract, :terminated, organization: customer.organization, customer:) }

        it "does not enqueue its refresh job" do
          described_class.perform_now

          expect(Invoices::RefreshDraftJob).not_to have_been_enqueued.with(invoice:)
        end
      end
    end
  end
end
