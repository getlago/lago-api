# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::CreateJob, type: :job do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:params) do
    {
      billable_metric_id: billable_metric.id,
      charge_model: 'standard',
      invoice_display_name: 'charge1',
      min_amount_cents: 100
    }
  end

  before do
    allow(Charges::CreateService).to receive(:call).with(plan:, params:).and_return(BaseService::Result.new)
  end

  it 'calls the service' do
    described_class.perform_now(plan:, params:)

    expect(Charges::CreateService).to have_received(:call)
  end
end
