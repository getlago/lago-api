# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyUsages::ComputeJob do
  subject(:compute_job) { described_class }

  let(:subscription) { create(:subscription) }
  let(:timestamp) { Time.current }

  let(:result) { BaseService::Result.new }

  describe ".perform" do
    it "delegates to DailyUsages::ComputeService" do
      allow(DailyUsages::ComputeService).to receive(:call)
        .with(subscription:, timestamp:)
        .and_return(result)

      compute_job.perform_now(subscription, timestamp:)

      expect(DailyUsages::ComputeService).to have_received(:call)
        .with(subscription:, timestamp:).once
    end
  end

  describe "#lock_key_arguments" do
    let(:customer) { create(:customer, timezone: "Europe/Paris") }
    let(:subscription) { create(:subscription, customer:) }

    it "normalizes the timestamp to the date in customer timezone" do
      timestamp = Time.zone.parse("2024-01-15 10:00:00 UTC")

      job = described_class.new(subscription, timestamp:)

      expected_date = Time.zone.parse("2024-01-15T11:00:00+01:00").to_date
      expect(job.lock_key_arguments).to eq([subscription.id, expected_date])
    end

    it "returns the same lock key for different timestamps on the same day in customer timezone" do
      morning_timestamp = Time.zone.parse("2024-01-15 23:00:00 UTC")
      evening_timestamp = Time.zone.parse("2024-01-16 00:00:00 UTC")

      morning_job = described_class.new(subscription, timestamp: morning_timestamp)
      evening_job = described_class.new(subscription, timestamp: evening_timestamp)

      expect(morning_job.lock_key_arguments).to eq(evening_job.lock_key_arguments)
    end

    it "returns different lock keys for timestamps on different days in customer timezone" do
      first_day_timestamp = Time.zone.parse("2024-01-15 00:00:00 UTC")
      second_day_timestamp = Time.zone.parse("2024-01-15 23:00:00 UTC")

      first_job = described_class.new(subscription, timestamp: first_day_timestamp)
      second_job = described_class.new(subscription, timestamp: second_day_timestamp)

      expect(first_job.lock_key_arguments).not_to eq(second_job.lock_key_arguments)
    end

    it "returns different lock keys for different subscriptions" do
      timestamp = Time.zone.parse("2024-01-15 10:00:00 UTC")
      other_subscription = create(:subscription, customer:)

      job1 = described_class.new(subscription, timestamp:)
      job2 = described_class.new(other_subscription, timestamp:)

      expect(job1.lock_key_arguments).not_to eq(job2.lock_key_arguments)
    end
  end
end
