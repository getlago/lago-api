# frozen_string_literal: true

require "rails_helper"

describe Clock::MarkInvoicesAsPaymentOverdueJob, job: true do
  subject { described_class }

  describe ".perform" do
    let!(:overdue_invoice_1) { create(:invoice, payment_due_date: 1.day.ago) }
    let!(:overdue_invoice_2) { create(:invoice, payment_due_date: 2.days.ago) }

    it "marks expected invoices as payment overdue" do
      create(:invoice, :draft, payment_due_date: 1.day.ago)
      create(:invoice, payment_status: :succeeded, payment_due_date: 1.day.ago)
      create(:invoice, payment_due_date: 1.day.ago, payment_dispute_lost_at: 1.day.ago)
      create(:invoice, payment_due_date: nil)
      create(:invoice, payment_due_date: 1.day.from_now)

      expect do
        described_class.perform_now
      end.to have_enqueued_job(Invoices::Payments::MarkOverdueJob).with(invoice: overdue_invoice_1)
        .and have_enqueued_job(Invoices::Payments::MarkOverdueJob).with(invoice: overdue_invoice_2)
    end
  end
end
