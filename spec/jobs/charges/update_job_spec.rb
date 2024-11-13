# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::UpdateJob, type: :job do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, plan:) }
  let(:cascade_options) { {} }
  let(:params) do
    {
      properties: {}
    }
  end

  before do
    allow(Charges::UpdateService).to receive(:call).with(charge:, params:, cascade_options:).and_return(BaseService::Result.new)
  end

  it 'calls the service' do
    described_class.perform_now(charge:, params:, cascade_options:)

    expect(Charges::UpdateService).to have_received(:call)
  end
end
