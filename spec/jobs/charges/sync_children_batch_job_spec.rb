# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::SyncChildrenBatchJob do
  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:child_plan) { create(:plan, organization:, parent_id: plan.id) }
  let(:charge) { create(:standard_charge, organization:, plan:, billable_metric:) }
  let(:children_plans_ids) { [child_plan.id] }

  before do
    allow(Charges::SyncChildrenBatchService).to receive(:call!)
      .with(children_plans_ids:, charge:)
      .and_call_original
  end

  it "calls the sync children batch service" do
    described_class.perform_now(children_plans_ids:, charge:)

    expect(Charges::SyncChildrenBatchService).to have_received(:call!)
      .with(children_plans_ids:, charge:)
  end
end
