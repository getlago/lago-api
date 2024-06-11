# frozen_string_literal: true

require "rails_helper"

describe Clock::MarkInvoicesAsPaymentOverdueJob, job: true do
  subject { described_class }

  describe ".perform" do
    let(:overdue_invoice) { create(:invoice, payment_due_date: 1.day.ago) }

    before do
      overdue_invoice
    end

    it "marks expected invoices as payment overdue" do
      create(:invoice, :draft, payment_due_date: 1.day.ago)
      create(:invoice, :succeeded, payment_due_date: 1.day.ago)
      create(:invoice, payment_due_date: 1.day.ago, payment_dispute_lost_at: 1.day.ago)
      create(:invoice, payment_due_date: nil)
      create(:invoice, payment_due_date: 1.day.from_now)

      described_class.perform_now
      expect(Invoice.payment_overdue).to eq([overdue_invoice])
    end

    it "enqueues a SendWebhookJob" do
      expect do
        described_class.perform_now
      end.to have_enqueued_job(SendWebhookJob).with("invoice.payment_overdue", Invoice)
    end
  end
end
