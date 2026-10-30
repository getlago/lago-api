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

  describe "index usage" do
    # Force PostgreSQL to use indexes even on a tiny test dataset so we can
    # verify the planner CAN use them for the query patterns the job produces.
    # enable_sort is also disabled: the query orders by payment_due_date, and
    # the partial index is the only one providing that order, so disabling the
    # sort removes the planner's freedom to pick a different index on a tiny
    # dataset (the source of the flake). The id tiebreaker still uses an
    # incremental sort on top of the index.
    around do |example|
      ActiveRecord::Base.connection.execute("SET enable_seqscan = off")
      ActiveRecord::Base.connection.execute("SET enable_sort = off")
      example.run
    ensure
      ActiveRecord::Base.connection.execute("SET enable_sort = on")
      ActiveRecord::Base.connection.execute("SET enable_seqscan = on")
    end

    it "uses the partial index on payment_due_date for the overdue invoice lookup" do
      create(:invoice, payment_due_date: 1.day.ago)

      plan = Invoice
        .finalized
        .not_payment_succeeded
        .where(payment_overdue: false)
        .where(payment_dispute_lost_at: nil)
        .where(payment_due_date: ...Time.current)
        .order(:payment_due_date, :id)
        .limit(1000)
        .explain
        .inspect

      expect(plan).to include("index_invoices_on_payment_due_date")
    end
  end
end
