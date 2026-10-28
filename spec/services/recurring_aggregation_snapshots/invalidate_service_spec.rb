# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::InvalidateService do
  subject(:invalidate_service) { described_class.new(subscription:, codes:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:charge) { create(:standard_charge, organization:, billable_metric: create(:sum_billable_metric, organization:)) }
  let(:subscription) { create(:subscription, organization:, customer:, plan: charge.plan) }
  let(:codes) { [] }

  let(:previous_subscription) do
    create(:subscription, :terminated, organization:, customer:, plan: charge.plan, external_id: subscription.external_id)
  end
  let(:other_charge) { create(:standard_charge, organization:, plan: charge.plan) }
  let(:other_subscription) { create(:subscription, organization:, customer:, plan: charge.plan) }

  let!(:other_charge_snapshot) { create(:recurring_aggregation_snapshot, subscription:, charge: other_charge) }
  let!(:other_subscription_snapshot) { create(:recurring_aggregation_snapshot, subscription: other_subscription, charge:) }

  before do
    create(:recurring_aggregation_snapshot, subscription:, charge:)
    create(:recurring_aggregation_snapshot, subscription: previous_subscription, charge:)
  end

  describe "#call" do
    it "deletes the snapshots of every subscription sharing the external id" do
      expect(invalidate_service.call).to be_success

      expect(RecurringAggregationSnapshot.all).to eq([other_subscription_snapshot])
    end

    context "with codes" do
      let(:codes) { [charge.billable_metric.code] }

      it "only deletes the snapshots of the matching billable metrics" do
        invalidate_service.call

        expect(RecurringAggregationSnapshot.all).to match_array([other_charge_snapshot, other_subscription_snapshot])
      end
    end
  end
end
