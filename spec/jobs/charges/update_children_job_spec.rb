# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::UpdateChildrenJob do
  let(:charge) { create(:standard_charge) }
  let(:old_parent_attrs) { charge.attributes }
  let(:old_parent_filters_attrs) { charge.filters.map(&:attributes) }
  let(:old_parent_applied_pricing_unit_attrs) { charge.applied_pricing_unit&.attributes }
  let(:params) { {properties: {}} }

  before do
    allow(Charges::UpdateChildrenService).to receive(:call!)
  end

  it "calls the update children service" do
    described_class.perform_now(
      params:,
      old_parent_attrs:,
      old_parent_filters_attrs:,
      old_parent_applied_pricing_unit_attrs:
    )

    expect(Charges::UpdateChildrenService).to have_received(:call!).with(
      params:,
      old_parent_attrs:,
      old_parent_filters_attrs:,
      old_parent_applied_pricing_unit_attrs:
    )
  end
end
