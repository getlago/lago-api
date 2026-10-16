# frozen_string_literal: true

require "rails_helper"

describe Clock::ReconcileX402SettlementsJob, job: true do
  subject(:job) { described_class }

  let(:organization) { create(:organization, feature_flags: ["x402_payments"]) }
  let(:x402_connection) { create(:x402_connection, organization:) }
  let(:settlement) { create(:x402_settlement, :pending, x402_connection:, reconcile_after: 1.minute.ago) }

  before { settlement }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  it "enqueues a reconciliation for a row whose window has closed" do
    expect { job.perform_now }.to have_enqueued_job(X402::Settlements::ReconcileJob).with(settlement)
  end

  context "without the x402 feature flag" do
    let(:organization) { create(:organization, feature_flags: []) }

    it "still enqueues the row" do
      expect { job.perform_now }.to have_enqueued_job(X402::Settlements::ReconcileJob).with(settlement)
    end
  end

  context "with a Solana row" do
    let(:settlement) { create(:x402_settlement, :solana, :pending, reconcile_after: 1.minute.ago) }

    it "enqueues the row" do
      expect { job.perform_now }.to have_enqueued_job(X402::Settlements::ReconcileJob).with(settlement)
    end
  end

  context "with a row whose window is still open" do
    let(:settlement) { create(:x402_settlement, :pending, x402_connection:, reconcile_after: 1.minute.from_now) }

    it "leaves it for a later run" do
      expect { job.perform_now }.not_to have_enqueued_job(X402::Settlements::ReconcileJob)
    end
  end

  context "with a resolved row" do
    let(:settlement) { create(:x402_settlement, :failed, x402_connection:, reconcile_after: 1.minute.ago) }

    it "leaves it alone" do
      expect { job.perform_now }.not_to have_enqueued_job(X402::Settlements::ReconcileJob)
    end
  end

  context "with a settled purchase left without a grant for two minutes" do
    let(:settlement) { create(:x402_settlement, x402_connection:, updated_at: 3.minutes.ago) }

    it "enqueues the row" do
      expect { job.perform_now }.to have_enqueued_job(X402::Settlements::ReconcileJob).with(settlement)
    end

    context "without the x402 feature flag" do
      let(:organization) { create(:organization, feature_flags: []) }

      it "still enqueues the row" do
        expect { job.perform_now }.to have_enqueued_job(X402::Settlements::ReconcileJob).with(settlement)
      end
    end
  end

  context "with a settled purchase younger than two minutes" do
    let(:settlement) { create(:x402_settlement, x402_connection:, updated_at: 1.minute.ago) }

    it "leaves it to the request that settled it" do
      expect { job.perform_now }.not_to have_enqueued_job(X402::Settlements::ReconcileJob)
    end
  end

  context "with a settled invoice payment left without a payment for two minutes" do
    let(:settlement) { create(:x402_settlement, :invoice_payment, x402_connection:, updated_at: 3.minutes.ago) }

    it "enqueues the row" do
      expect { job.perform_now }.to have_enqueued_job(X402::Settlements::ReconcileJob).with(settlement)
    end
  end

  context "with a settled invoice payment younger than two minutes" do
    let(:settlement) { create(:x402_settlement, :invoice_payment, x402_connection:, updated_at: 1.minute.ago) }

    it "leaves it to the request that settled it" do
      expect { job.perform_now }.not_to have_enqueued_job(X402::Settlements::ReconcileJob)
    end
  end

  describe "index usage" do
    around do |example|
      ActiveRecord::Base.connection.execute("SET enable_seqscan = off")
      example.run
    ensure
      ActiveRecord::Base.connection.execute("SET enable_seqscan = on")
    end

    let(:settlement) { create(:x402_settlement, x402_connection:, updated_at: 3.minutes.ago) }

    it "reads the purchases left without a grant through their partial index" do
      plan = X402::Settlement.grant_retry_due.order(:id).limit(1000).explain.inspect

      expect(plan).to include("index_x402_settlements_on_ungranted_id")
    end

    it "reads the invoice payments left without a payment through their partial index" do
      plan = X402::Settlement.payment_retry_due.order(:id).limit(1000).explain.inspect

      expect(plan).to include("index_x402_settlements_on_unpaid_id")
    end
  end
end
