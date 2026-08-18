# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::BillingPeriods::UpsertJob, job: true do
  subject(:perform) { described_class.perform_now(subscription_id) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, status: :active) }
  let(:subscription_id) { subscription.id }

  before { allow(Subscriptions::BillingPeriods::UpsertService).to receive(:call!).and_call_original }

  it "materializes the periods of the subscription" do
    expect { perform }.to change(SubscriptionBillingPeriod, :count).by(2)

    expect(Subscriptions::BillingPeriods::UpsertService).to have_received(:call!).with(subscription:)
  end

  # The sweep pages over ids, so one can be deleted between the enqueue and the run.
  context "when the subscription no longer exists" do
    let(:subscription_id) { SecureRandom.uuid }

    it "does nothing" do
      expect { perform }.not_to change(SubscriptionBillingPeriod, :count)

      expect(Subscriptions::BillingPeriods::UpsertService).not_to have_received(:call!)
    end
  end
end
