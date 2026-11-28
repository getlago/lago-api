# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::ConsumeContractRefreshedQueueJob, job: true do
  subject(:perform) { described_class.perform_now }

  before { allow(Contracts::ConsumeRefreshedQueueService).to receive(:call!) }

  it "runs one at a time" do
    expect(described_class.lock_strategy_class).to eq(ActiveJob::Uniqueness::Strategies::UntilExecuted)
    expect(described_class.lock_options).to eq(on_conflict: :log)
  end

  it "consumes the contract refreshed queue" do
    perform

    expect(Contracts::ConsumeRefreshedQueueService).to have_received(:call!)
  end
end
