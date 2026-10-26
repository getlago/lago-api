# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::InvalidateJob do
  subject(:invalidate_job) { described_class }

  let(:subscription) { create(:subscription) }
  let(:codes) { ["metric"] }

  before { allow(RecurringAggregationSnapshots::InvalidateService).to receive(:call!) }

  it "invalidates the recurring aggregation snapshots" do
    invalidate_job.perform_now(subscription, codes)

    expect(RecurringAggregationSnapshots::InvalidateService).to have_received(:call!).with(subscription:, codes:)
  end
end
