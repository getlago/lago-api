# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::BillingPeriods::BackfillOrganizationService do
  subject(:result) { described_class.call(organization:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }

  before { create(:subscription, organization:, customer:, plan:, status: :active) }

  it "materializes the periods of active subscriptions" do
    expect { result }.to change(SubscriptionBillingPeriod, :count).by(2)
    expect(result.processed_count).to eq(1)
    expect(result.failed_count).to eq(0)
  end

  it "skips subscriptions the writer would refuse" do
    create(:subscription, :pending, organization:, customer:, plan:)

    expect(result.processed_count).to eq(1)
  end

  # Backdated events keep arriving for these during the grace period, so an organization enabled
  # today would otherwise leave them with no covering period at all.
  it "materializes the final period of a recently terminated subscription" do
    create(
      :subscription, :terminated,
      organization:, customer:, plan:,
      started_at: 2.months.ago,
      terminated_at: 3.days.ago
    )

    expect { result }.to change(SubscriptionBillingPeriod, :count).by(3)
    expect(result.processed_count).to eq(2)
  end

  it "skips a subscription terminated before the grace period" do
    create(
      :subscription, :terminated,
      organization:, customer:, plan:,
      started_at: 6.months.ago,
      terminated_at: 2.months.ago
    )

    expect(result.processed_count).to eq(1)
  end

  context "when a subscription raises" do
    before do
      allow(Subscriptions::BillingPeriods::UpsertService).to receive(:call!).and_raise(StandardError, "boom")
      allow(Sentry).to receive(:capture_exception)
    end

    it "reports it and carries on" do
      expect(result.failed_count).to eq(1)
      expect(result.processed_count).to eq(0)
      expect(Sentry).to have_received(:capture_exception)
    end
  end
end
