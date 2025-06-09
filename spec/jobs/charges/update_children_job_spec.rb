# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::UpdateChildrenJob, type: :job do
  let(:charge) { create(:standard_charge) }
  let(:old_parent_attrs) { charge.attributes }
  let(:old_parent_filters_attrs) { charge.filters.map(&:attributes) }
  let(:params) do
    {
      properties: {}
    }
  end

  before do
    allow(Charges::UpdateChildrenService)
      .to receive(:call!)
      .with(charge:, params:, old_parent_attrs:, old_parent_filters_attrs:).and_call_original
  end

  it "calls the service" do
    described_class.perform_now(params:, old_parent_attrs:, old_parent_filters_attrs:)

    expect(Charges::UpdateChildrenService).to have_received(:call!)
  end
end
