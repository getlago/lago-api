# frozen_string_literal: true

require "rails_helper"

describe BillingSegments::ScheduleJob, job: true do
  subject { described_class }

  let(:customer) { create(:customer) }

  it_behaves_like "a unique job" do
    let(:job_args) { [customer.id] }
  end

  describe "unique" do
    it "releases its lock once it starts, so a request made during a run is not dropped" do
      expect(described_class.lock_strategy_class).to eq(ActiveJob::Uniqueness::Strategies::UntilExecuting)
    end
  end

  describe ".perform" do
    before { allow(BillingOperations::ProcessService).to receive(:call!).and_call_original }

    it "processes the customer's pending billing operations" do
      expect { described_class.perform_now(customer.id) }
        .not_to have_enqueued_job(BillingOperations::ProcessJob)

      expect(BillingOperations::ProcessService).to have_received(:call!).with(customer:, timestamp: kind_of(Time))
    end
  end
end
