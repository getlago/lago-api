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

  context "with a contract" do
    subject(:perform) { described_class.perform_now(contract) }

    let(:contract) { create(:contract) }
    let(:contract_rate_card) { build_stubbed(:contract_rate_card) }
    let(:failed_rate_cards) { [] }
    let(:contract_backfill) do
      RecurringAggregationSnapshots::ContractBackfillService::Result.new.tap { it.failed_rate_cards = failed_rate_cards }
    end

    before do
      allow(RecurringAggregationSnapshots::ContractBackfillService).to receive(:call).with(contract:).and_return(contract_backfill)
    end

    it "backfills the contract" do
      perform

      expect(RecurringAggregationSnapshots::ContractBackfillService).to have_received(:call).with(contract:)
      expect(RecurringAggregationSnapshots::BackfillService).not_to have_received(:call)
    end

    context "when a rate card failed" do
      let(:failed_rate_cards) { [contract_rate_card] }

      it "raises once the attempts are exhausted" do
        assert_performed_jobs(3, only: [described_class]) do
          expect { described_class.perform_later(contract) }
            .to raise_error(described_class::ChargesFailedError, /Rate cards #{contract_rate_card.id} failed to backfill/)
        end
      end
    end

    context "when the contract is no longer active" do
      let(:contract_backfill) { RecurringAggregationSnapshots::ContractBackfillService::Result.new.not_allowed_failure!(code: "contract_not_active") }

      it "does nothing" do
        expect { perform }.not_to raise_error
      end
    end
  end
end
