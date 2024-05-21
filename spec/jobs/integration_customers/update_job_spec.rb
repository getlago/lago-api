# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationCustomers::UpdateJob, type: :job do
  subject(:create_job) { described_class }

  let(:update_service) { instance_double(IntegrationCustomers::UpdateService) }
  let(:integration) { create(:netsuite_integration) }
  let(:integration_customer) { create(:netsuite_customer, integration:) }
  let(:result) { BaseService::Result.new }
  let(:integration_customer_params) do
    {
      sync_with_provider: true
    }
  end

  before do
    allow(IntegrationCustomers::UpdateService).to receive(:new).and_return(update_service)
    allow(update_service).to receive(:call).and_return(result)
  end

  it 'calls the update service' do
    described_class.perform_now(integration_customer_params:, integration:, integration_customer:)

    expect(IntegrationCustomers::UpdateService).to have_received(:new)
    expect(update_service).to have_received(:call)
  end
end
