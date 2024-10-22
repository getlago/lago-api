# frozen_string_literal: true

require 'rails_helper'

describe Clockwork do
  after { Clockwork::Test.clear! }

  let(:clock_file) { Rails.root.join('clock.rb') }

  describe 'schedule:bill_customers' do
    let(:job) { 'schedule:bill_customers' }
    let(:start_time) { Time.zone.parse('1 Apr 2022 00:01:00') }
    let(:end_time) { Time.zone.parse('1 Apr 2022 01:01:00') }

    it 'enqueue a subscription biller job' do
      Clockwork::Test.run(
        file: clock_file,
        start_time:,
        end_time:,
        tick_speed: 1.second
      )

      expect(Clockwork::Test).to be_ran_job(job)
      expect(Clockwork::Test.times_run(job)).to eq(1)

      Clockwork::Test.block_for(job).call
      expect(Clock::SubscriptionsBillerJob).to have_been_enqueued
    end
  end

  describe 'schedule:activate_subscriptions' do
    let(:job) { 'schedule:activate_subscriptions' }
    let(:start_time) { Time.zone.parse('1 Apr 2022 00:01:00') }
    let(:end_time) { Time.zone.parse('1 Apr 2022 00:31:00') }

    it 'enqueue a activate subscriptions job' do
      Clockwork::Test.run(
        file: clock_file,
        start_time:,
        end_time:,
        tick_speed: 1.second
      )

      expect(Clockwork::Test).to be_ran_job(job)
      expect(Clockwork::Test.times_run(job)).to eq(6)

      Clockwork::Test.block_for(job).call
      expect(Clock::ActivateSubscriptionsJob).to have_been_enqueued
    end
  end

  describe 'schedule:post_validate_events' do
    let(:job) { 'schedule:post_validate_events' }
    let(:start_time) { Time.zone.parse('1 Apr 2022 01:00:00') }
    let(:end_time) { Time.zone.parse('1 Apr 2022 03:00:00') }

    it 'enqueue a activate subscriptions job' do
      Clockwork::Test.run(
        file: clock_file,
        start_time:,
        end_time:,
        tick_speed: 1.second
      )

      expect(Clockwork::Test).to be_ran_job(job)
      expect(Clockwork::Test.times_run(job)).to eq(2)

      Clockwork::Test.block_for(job).call
      expect(Clock::EventsValidationJob).to have_been_enqueued
    end
  end

  describe 'schedule:refresh_lifetime_usages' do
    let(:job) { 'schedule:refresh_lifetime_usages' }
    let(:start_time) { Time.zone.parse('1 Apr 2022 00:01:00') }
    let(:end_time) { Time.zone.parse('1 Apr 2022 00:31:00') }

    it 'enqueue a refresh lifetime usages job' do
      Clockwork::Test.run(
        file: clock_file,
        start_time:,
        end_time:,
        tick_speed: 1.second
      )

      expect(Clockwork::Test).to be_ran_job(job)
      expect(Clockwork::Test.times_run(job)).to eq(6)

      Clockwork::Test.block_for(job).call
      expect(Clock::RefreshLifetimeUsagesJob).to have_been_enqueued
    end

    context "with a custom refresh interval configured" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('LAGO_LIFETIME_USAGE_REFRESH_INTERVAL_SECONDS').and_return('150')
      end

      it 'uses the ENV["LAGO_LIFETIME_USAGE_REFRESH_INTERVAL_SECONDS"] to set a custom period' do
        Clockwork::Test.run(
          file: clock_file,
          start_time:,
          end_time:,
          tick_speed: 1.second
        )

        expect(Clockwork::Test).to be_ran_job(job)
        expect(Clockwork::Test.times_run(job)).to eq(12)

        Clockwork::Test.block_for(job).call
        expect(Clock::RefreshLifetimeUsagesJob).to have_been_enqueued

        expect(ENV).to have_received(:[]).with('LAGO_LIFETIME_USAGE_REFRESH_INTERVAL_SECONDS')
      end
    end
  end

  describe 'schedule:' do
    let(:job) { 'schedule:compute_daily_usage' }
    let(:start_time) { Time.zone.parse('1 Apr 2022 00:01:00') }
    let(:end_time) { Time.zone.parse('1 Apr 2022 01:01:00') }

    it 'enqueue a activate subscriptions job' do
      Clockwork::Test.run(
        file: clock_file,
        start_time:,
        end_time:,
        tick_speed: 1.second
      )

      expect(Clockwork::Test).to be_ran_job(job)
      expect(Clockwork::Test.times_run(job)).to eq(1)

      Clockwork::Test.block_for(job).call
      expect(Clock::ComputeAllDailyUsagesJob).to have_been_enqueued
    end
  end
end
