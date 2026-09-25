# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::CreatePayInAdvanceJob do
  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization:) }
  let(:charge) { create(:standard_charge, :pay_in_advance, organization:, plan: subscription.plan) }
  let(:event) { create(:event, organization:, external_subscription_id: subscription.external_id) }
  let(:result) { Fees::CreatePayInAdvanceService::Result.new }

  it "delegates to the pay_in_advance aggregation service" do
    allow(Fees::CreatePayInAdvanceService).to receive(:call)
      .with(
        metered_item: instance_of(Fees::ChargeService::MeteredItem),
        billing_context: instance_of(Billing::Context),
        billing_at: nil
      )
      .and_return(result)

    described_class.perform_now(charge:, event:)

    expect(Fees::CreatePayInAdvanceService).to have_received(:call)
  end

  context "when the event has no billing context" do
    let(:event) do
      create(:event, organization:, external_subscription_id: "unknown-#{SecureRandom.uuid}")
    end

    before do
      allow(Fees::CreatePayInAdvanceService).to receive(:call)
      allow(Rails.logger).to receive(:error)
    end

    it "skips the service call and logs the event" do
      described_class.perform_now(charge:, event:)

      expect(Fees::CreatePayInAdvanceService).not_to have_received(:call)
      expect(Rails.logger).to have_received(:error)
        .with(/no billing context for event.*charge_id=#{charge.id}/)
    end
  end

  describe ".retry_wait" do
    it "grows polynomially and adds the jitter on each retry" do
      jitter = described_class::RETRY_JITTER

      expect(described_class.retry_wait(1)).to be_between(1**4 + jitter.min, 1**4 + jitter.max)
      expect(described_class.retry_wait(2)).to be_between(2**4 + jitter.min, 2**4 + jitter.max)
      expect(described_class.retry_wait(3)).to be_between(3**4 + jitter.min, 3**4 + jitter.max)
    end

    it "keeps the jitter within RETRY_JITTER" do
      jitters = Array.new(50) { described_class.retry_wait(1) - (1**4) }

      expect(jitters).to all(be_between(described_class::RETRY_JITTER.min, described_class::RETRY_JITTER.max))
    end
  end

  describe "retry_on" do
    before do
      allow(Fees::CreatePayInAdvanceService).to receive(:call)
        .and_raise(Events::Stores::Clickhouse::MemoryLimitError)
    end

    it "retries on a Clickhouse memory limit error" do
      assert_performed_jobs(25, only: [described_class]) do
        expect do
          described_class.perform_later(charge:, event:)
        end.to raise_error(Events::Stores::Clickhouse::MemoryLimitError)
      end
    end
  end
end
