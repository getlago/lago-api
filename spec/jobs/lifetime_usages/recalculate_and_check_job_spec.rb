# frozen_string_literal: true

require "rails_helper"

RSpec.describe LifetimeUsages::RecalculateAndCheckJob do
  let(:organization) { create(:organization, :premium, premium_integrations:) }
  let(:lifetime_usage) { create(:lifetime_usage, organization:) }

  let(:premium_integrations) { ["progressive_billing"] }

  it_behaves_like "a configurable queue", "billing_low_priority", "SIDEKIQ_BILLING" do
    let(:arguments) { lifetime_usage }
  end

  it "delegates to the Calculate service" do
    allow(LifetimeUsages::CalculateService).to receive(:call!)
    allow(LifetimeUsages::CheckThresholdsService).to receive(:call!)
    described_class.perform_now(lifetime_usage)
    expect(LifetimeUsages::CalculateService).to have_received(:call!).with(lifetime_usage:, current_usage: nil)
    expect(LifetimeUsages::CheckThresholdsService).not_to have_received(:call!)
  end

  context "when premium", :premium do
    it "delegates to the RecalculateAndCheck service" do
      allow(LifetimeUsages::CalculateService).to receive(:call!)
      allow(LifetimeUsages::CheckThresholdsService).to receive(:call!)
      described_class.perform_now(lifetime_usage)
      expect(LifetimeUsages::CalculateService).to have_received(:call!).with(lifetime_usage:, current_usage: nil)
      expect(LifetimeUsages::CheckThresholdsService).to have_received(:call!).with(lifetime_usage:)
    end

    context "when progressive billing is disabled" do
      let(:premium_integrations) { [] }

      it "delegates to the RecalculateAndCheck service" do
        allow(LifetimeUsages::CalculateService).to receive(:call!)
        allow(LifetimeUsages::CheckThresholdsService).to receive(:call!)
        described_class.perform_now(lifetime_usage)
        expect(LifetimeUsages::CalculateService).to have_received(:call!).with(lifetime_usage:, current_usage: nil)
        expect(LifetimeUsages::CheckThresholdsService).not_to have_received(:call!)
      end
    end
  end

  describe "retry_on" do
    [
      [BaseLockService::FailedToAcquireLock.new("customer-1-prepaid_credit"), 25],
      [ActiveRecord::StaleObjectError.new("Attempted to update a stale object: Wallet."), 25]
    ].each do |error, attempts|
      error_class = error.class

      context "when a #{error_class} error is raised" do
        before do
          allow(LifetimeUsages::CalculateService).to receive(:call).and_raise(error)
        end

        it "raises a #{error_class.name} error and retries" do
          assert_performed_jobs(attempts, only: [described_class]) do
            expect do
              described_class.perform_later(lifetime_usage)
            end.to raise_error(error_class)
          end
        end
      end
    end
  end

  describe "in-process lock retry when invoked inline with current_usage" do
    let(:current_usage) { SubscriptionUsage.new }

    before do
      allow(LifetimeUsages::CalculateService).to receive(:call!)
      allow(LifetimeUsages::CheckThresholdsService).to receive(:call!)
    end

    it "forwards the current_usage to the Calculate service" do
      described_class.perform_now(lifetime_usage, current_usage:)
      expect(LifetimeUsages::CalculateService).to have_received(:call!).with(lifetime_usage:, current_usage:)
    end

    [
      BaseLockService::FailedToAcquireLock.new("customer-1-prepaid_credit"),
      ActiveRecord::StaleObjectError.new("Attempted to update a stale object: Wallet.")
    ].each do |error|
      context "when a #{error.class} is raised then resolves" do
        before do
          stub_const("ApplicationJob::MAX_LOCK_RETRY_DELAY", 1)
          call_count = 0
          allow(LifetimeUsages::CalculateService).to receive(:call!) do
            call_count += 1
            raise error if call_count == 1
          end
        end

        it "retries in-process without raising ActiveJob::SerializationError" do
          expect { described_class.perform_now(lifetime_usage, current_usage:) }.not_to raise_error
          expect(LifetimeUsages::CalculateService).to have_received(:call!).twice
        end
      end

      context "when a #{error.class} never resolves" do
        before do
          stub_const("ApplicationJob::MAX_LOCK_RETRY_ATTEMPTS", 3)
          stub_const("ApplicationJob::MAX_LOCK_RETRY_DELAY", 1)
          allow(LifetimeUsages::CalculateService).to receive(:call!).and_raise(error)
        end

        it "exhausts in-process retries and raises without reaching retry_on" do
          expect { described_class.perform_now(lifetime_usage, current_usage:) }
            .to raise_error(described_class::InlineLockRetryExhausted)
          expect(LifetimeUsages::CalculateService).to have_received(:call!).exactly(3).times
        end
      end
    end
  end

  describe "discard_on" do
    context "when an Idempotency::IdempotencyError is raised", :premium do
      before do
        allow(LifetimeUsages::CalculateService).to receive(:call!)
        allow(LifetimeUsages::CheckThresholdsService).to receive(:call!)
          .and_raise(Idempotency::IdempotencyError.new("already exists"))
      end

      it "discards the job without raising or retrying" do
        assert_performed_jobs(1, only: [described_class]) do
          expect do
            described_class.perform_later(lifetime_usage)
          end.not_to raise_error
        end
      end
    end
  end
end
