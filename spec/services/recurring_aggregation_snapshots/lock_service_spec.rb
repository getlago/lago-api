# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::LockService do
  subject(:lock_service) { described_class.new(subscription:, charge:, to_datetime:) }

  let(:subscription) { create(:subscription) }
  let(:charge) { create(:standard_charge, plan: subscription.plan) }
  let(:to_datetime) { Time.zone.parse("2026-09-30T23:59:59.999999") }
  let(:lock_key) { "recurring-aggregation-snapshot-#{subscription.id}-#{charge.id}-2026-09-30T23:59:59.999999Z" }

  describe "#call" do
    it "takes an advisory lock" do
      expect(ActiveRecord::Base.advisory_lock_exists?(lock_key)).to be false

      lock_service.call do
        expect(ActiveRecord::Base.advisory_lock_exists?(lock_key)).to be true
      end

      expect(ActiveRecord::Base.advisory_lock_exists?(lock_key)).to be false
    end

    it "exposes the block return value on the result" do
      expect(lock_service.call { :done }.value).to eq(:done)
    end

    context "when the lock is held by another connection", transaction: false do
      around do |test|
        with_advisory_lock(lock_key, lock_released_after: 1.second) do
          test.run
        end
      end

      it "waits for it instead of failing" do
        expect(lock_service.call { :done }.value).to eq(:done)
      end
    end
  end
end
