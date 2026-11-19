# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::ExpirePendingTopUpsJob, job: true do
  subject(:job) { described_class }

  let(:wallet) { create(:wallet) }
  let(:stale) { build_top_up({}) }

  def build_top_up(attributes, invoice_status: :open, total_paid_amount_cents: 0)
    invoice = create(:invoice, :credit, customer: wallet.customer, organization: wallet.organization,
      status: invoice_status, total_amount_cents: 1_000, total_paid_amount_cents:)

    create(:wallet_transaction, {wallet:, invoice:, status: :pending, settled_at: nil, transaction_status: :purchased,
                                 invoice_requires_successful_payment: true, created_at: 2.hours.ago}.merge(attributes))
  end

  before { stale }

  it "enqueues the expiration of a pending top-up older than an hour" do
    expect { job.perform_now }
      .to have_enqueued_job(WalletTransactions::ExpirePendingJob).with(stale)
  end

  context "when the top-up was created minutes ago" do
    let(:fresh) { build_top_up({created_at: 10.minutes.ago}) }

    before { fresh }

    it "leaves it alone until the hour passes" do
      expect { job.perform_now }
        .not_to have_enqueued_job(WalletTransactions::ExpirePendingJob).with(fresh)
    end
  end

  context "when the top-up does not require a successful payment" do
    let(:finalized) { build_top_up({invoice_requires_successful_payment: false}) }

    before { finalized }

    it "skips it, since the customer manages its finalized invoice" do
      expect { job.perform_now }
        .not_to have_enqueued_job(WalletTransactions::ExpirePendingJob).with(finalized)
    end
  end

  context "when its invoice is not open" do
    let(:generating) { build_top_up({}, invoice_status: :generating) }
    let(:tax_failed) { build_top_up({}, invoice_status: :failed) }

    before do
      generating
      tax_failed
    end

    it "skips them, since they cannot expire" do
      job.perform_now

      expect(WalletTransactions::ExpirePendingJob).not_to have_been_enqueued.with(generating)
      expect(WalletTransactions::ExpirePendingJob).not_to have_been_enqueued.with(tax_failed)
    end
  end

  context "when a merchant recorded part of its invoice manually" do
    let(:partly_paid) { build_top_up({}, total_paid_amount_cents: 400) }

    before { partly_paid }

    it "skips it, since the merchant is collecting it" do
      expect { job.perform_now }
        .not_to have_enqueued_job(WalletTransactions::ExpirePendingJob).with(partly_paid)
    end
  end

  context "when the top-up is settled or failed" do
    let(:settled) { build_top_up({status: :settled, settled_at: Time.current}) }
    let(:failed) { build_top_up({status: :failed, failed_at: Time.current}) }

    before do
      settled
      failed
    end

    it "skips them" do
      job.perform_now

      expect(WalletTransactions::ExpirePendingJob).not_to have_been_enqueued.with(settled)
      expect(WalletTransactions::ExpirePendingJob).not_to have_been_enqueued.with(failed)
    end
  end
end
