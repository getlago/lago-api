# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::BillingPeriods::RefreshAllJob, job: true do
  subject(:perform) { described_class.perform_now(owner) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:owner) { customer }
  let(:next_cursor) { nil }

  let(:result) { Subscriptions::BillingPeriods::RefreshAllService::Result.new }

  before do
    result.enqueued_count = 1
    result.next_cursor = next_cursor

    allow(Subscriptions::BillingPeriods::RefreshAllService).to receive(:call!)
      .with(owner:, cursor: nil).and_return(result)
  end

  context "when a page is left to walk" do
    let(:next_cursor) { SecureRandom.uuid }

    it "re-enqueues itself on the cursor" do
      expect { perform }.to have_enqueued_job(described_class).with(owner, next_cursor)
    end
  end

  context "when no page is left" do
    let(:next_cursor) { nil }

    it "stops" do
      expect { perform }.not_to have_enqueued_job(described_class)
    end
  end

  describe "unique" do
    # A timezone change committing mid-walk may have been missed by the subscriptions already
    # walked past, so the enqueue it makes must not be dropped as a duplicate.
    it "has unique :until_executing constraint" do
      expect(described_class.lock_strategy_class).to eq(ActiveJob::Uniqueness::Strategies::UntilExecuting)
    end
  end
end
