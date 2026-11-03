# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::BackfillJob do
  subject(:perform) { described_class.perform_now(subscription) }

  let(:subscription) { create(:subscription) }
  let(:charge) { build_stubbed(:standard_charge) }
  let(:backfill) { RecurringAggregationSnapshots::BackfillService::Result.new.tap { it.failed_charges = failed_charges } }
  let(:failed_charges) { [] }

  before { allow(RecurringAggregationSnapshots::BackfillService).to receive(:call).with(subscription:).and_return(backfill) }

  it "backfills the subscription" do
    perform

    expect(RecurringAggregationSnapshots::BackfillService).to have_received(:call).with(subscription:)
  end

  it_behaves_like "a unique job" do
    let(:job_args) { [subscription] }
  end

  context "when a charge failed" do
    let(:failed_charges) { [charge] }

    it "retries the subscription" do
      expect { perform }.to have_enqueued_job(described_class).with(subscription)
    end

    it "raises once the attempts are exhausted" do
      assert_performed_jobs(3, only: [described_class]) do
        expect { described_class.perform_later(subscription) }
          .to raise_error(described_class::ChargesFailedError, /Charges #{charge.id} failed to backfill/)
      end
    end
  end

  context "when the subscription is no longer active" do
    let(:backfill) { RecurringAggregationSnapshots::BackfillService::Result.new.not_allowed_failure!(code: "subscription_not_active") }

    it "does nothing" do
      expect { perform }.not_to raise_error
    end
  end

  context "when the backfill fails otherwise" do
    let(:backfill) { RecurringAggregationSnapshots::BackfillService::Result.new.service_failure!(code: "error", message: "failed") }

    it "raises" do
      expect { perform }.to raise_error(BaseService::ServiceFailure)
    end
  end
end
