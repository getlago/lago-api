# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::CreateChildrenJob, type: :job do
  let(:billable_metric) { create(:billable_metric) }
  let(:plan) { create(:plan, organization: billable_metric.organization) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:params) do
    {
      billable_metric_id: billable_metric.id,
      charge_model: "standard",
      invoice_display_name: "charge1",
      min_amount_cents: 100
    }
  end

  before do
    allow(Charges::CreateChildrenService).to receive(:call!)
      .with(charge:, payload: params)
      .and_call_original
  end

  it "calls the service" do
    described_class.perform_now(charge:, payload: params)

    expect(Charges::CreateChildrenService).to have_received(:call!)
  end
end
