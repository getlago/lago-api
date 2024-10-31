# frozen_string_literal: true

require 'rails_helper'

describe Clock::RetryGeneratingSubscriptionInvoicesJob, job: true do
  subject { described_class }

  describe '.perform' do
    let(:old_generating_invoice) { create(:invoice, :generating, created_at: 5.days.ago) }

    before do
      old_generating_invoice
    end

    it "does not enqueue a BillSubscriptionJob for this invoice (missing subscriptions)" do
      expect do
        described_class.perform_now
      end.not_to have_enqueued_job(BillSubscriptionJob)
    end

    context "with an actual invoice that should be retried" do
      let(:old_generating_invoice) { create(:invoice, :subscription, created_at: 5.days.ago) }

      before do
        old_generating_invoice.update(status: :generating)
      end

      it "does enqueue a BillSubscriptionJob for this invoice " do
        expect do
          described_class.perform_now
        end.to have_enqueued_job(BillSubscriptionJob)
      end

      context "with an existing invoice error" do
        let(:invoice_error) { InvoiceError.create(id: old_generating_invoice.id) }

        before do
          invoice_error
        end

        it "does not enqueue a BillSubscriptionJob for this invoice" do
          expect do
            described_class.perform_now
          end.not_to have_enqueued_job(BillSubscriptionJob)
        end
      end
    end

    context "with an addon" do
      let(:old_generating_invoice) { create(:invoice, :add_on, created_at: 5.days.ago) }

      before do
        old_generating_invoice.update(status: :generating)
      end

      it "does not enqueue a BillSubscriptionJob for this invoice" do
        expect do
          described_class.perform_now
        end.not_to have_enqueued_job(BillSubscriptionJob)
      end
    end
  end
end
