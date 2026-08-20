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

  it "skips subscriptions that are not active" do
    create(:subscription, :pending, organization:, customer:, plan:)

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
