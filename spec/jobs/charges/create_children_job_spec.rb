# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::CreateChildrenJob, type: :job do
  let(:billable_metric) { create(:billable_metric) }
  let(:plan) { create(:plan, organization: billable_metric.organization) }
  let(:child_plan) { create(:plan, organization: billable_metric.organization, parent_id: plan.id) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:child_ids) { [child_plan.id] }

  let(:params) do
    {
      billable_metric_id: billable_metric.id,
      charge_model: "standard",
      invoice_display_name: "charge1",
      min_amount_cents: 100
    }
  end

  before do
    allow(Charges::CreateChildrenBatchJob).to receive(:perform_later)
      .with(child_ids:, charge:, payload: params)
      .and_call_original
  end

  it "calls the batch job" do
    described_class.perform_now(charge:, payload: params)

    expect(Charges::CreateChildrenBatchJob).to have_received(:perform_later).once
  end
end
