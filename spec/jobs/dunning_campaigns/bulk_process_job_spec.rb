# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaigns::BulkProcessJob do
  let(:result) { DunningCampaigns::BulkProcessService::Result.new }

  before do
    allow(DunningCampaigns::BulkProcessService)
      .to receive(:call)
      .and_return(result)
  end

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  it "uses the low_priority queue" do
    expect(described_class.new.queue_name).to eq("low_priority")
  end

  it "has a unique :until_executed constraint" do
    expect(described_class.lock_strategy_class).to eq(ActiveJob::Uniqueness::Strategies::UntilExecuted)
    expect(described_class.lock_options).to eq(on_conflict: :log, lock_ttl: 2.hours)
  end

  context "when premium features are enabled", :premium do
    it "calls DunningCampaigns::BulkProcessService service" do
      described_class.perform_now

      expect(DunningCampaigns::BulkProcessService)
        .to have_received(:call)
    end
  end

  context "when the run fails", :premium do
    around do |example|
      ActiveJob::Uniqueness.reset_manager!
      example.run
      ActiveJob::Uniqueness.test_mode!
    end

    before do
      allow(DunningCampaigns::BulkProcessService).to receive(:call).and_raise(ActiveRecord::QueryCanceled)
    end

    it "releases the lock so the next run can be enqueued" do
      described_class.perform_later

      expect { described_class.perform_now }.to raise_error(ActiveRecord::QueryCanceled)
      expect { described_class.perform_later }.to change { enqueued_jobs.count }.by(1) # rubocop:disable RSpec/ExpectChange
    end
  end

  it "does nothing" do
    described_class.perform_now

    expect(DunningCampaigns::BulkProcessService)
      .not_to have_received(:call)
  end
end
