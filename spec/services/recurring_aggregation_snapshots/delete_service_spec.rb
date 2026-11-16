# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::DeleteService do
  subject(:result) { described_class.call(subscription:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:charge) { create(:standard_charge, organization:, billable_metric: create(:sum_billable_metric, organization:)) }
  let(:subscription) { create(:subscription, :terminated, organization:, customer:, plan: charge.plan) }
  let(:other_charge) { create(:standard_charge, organization:, plan: charge.plan) }
  let(:other_subscription) { create(:subscription, organization:, customer:, plan: charge.plan) }

  let!(:other_subscription_snapshot) { create(:recurring_aggregation_snapshot, subscription: other_subscription, charge:) }

  before do
    create(:recurring_aggregation_snapshot, subscription:, charge:, to_datetime: 2.months.ago)
    create(:recurring_aggregation_snapshot, subscription:, charge:, to_datetime: 1.month.ago)
    create(:recurring_aggregation_snapshot, subscription:, charge: other_charge)
  end

  it "deletes every snapshot of the subscription" do
    expect(result).to be_success

    expect(RecurringAggregationSnapshot.all).to eq([other_subscription_snapshot])
  end
end
