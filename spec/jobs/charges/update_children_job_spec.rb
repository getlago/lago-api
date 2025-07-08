# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::UpdateChildrenJob, type: :job do
  let(:charge) { create(:standard_charge) }
  let(:child_charge) { create(:standard_charge, parent_id: charge.id) }
  let(:child_charge2) { create(:standard_charge, parent_id: charge.id) }
  let(:old_parent_attrs) { charge.attributes }
  let(:old_parent_filters_attrs) { charge.filters.map(&:attributes) }
  let(:old_parent_applied_pricing_unit_attrs) { charge.filters.map(&:attributes) }
  let(:params) do
    {
      properties: {}
    }
  end

  before do
    allow(Charges::UpdateChildrenBatchJob)
      .to receive(:perform_later)
      .with(child_ids: [child_charge.id, child_charge2.id], params:, old_parent_attrs:, old_parent_filters_attrs:, old_parent_applied_pricing_unit_attrs:)
      .and_call_original
  end

  it "calls the batch jobs" do
    described_class.perform_now(params:, old_parent_attrs:, old_parent_filters_attrs:, old_parent_applied_pricing_unit_attrs:)

    expect(Charges::UpdateChildrenBatchJob).to have_received(:perform_later).once
  end
end
