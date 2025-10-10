# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCustomers::CreateJob do
  subject(:create_job) { described_class }

  let(:integration) { create(:netsuite_integration) }
  let(:customer) { create(:customer) }
  let(:result) { BaseService::Result.new }
  let(:integration_customer_params) do
    {
      sync_with_provider: true
    }
  end

  before do
    allow(IntegrationCustomers::CreateService).to receive(:call).and_return(result)
  end

  it "calls the create service" do
    described_class.perform_now(integration_customer_params:, integration:, customer:)

    expect(IntegrationCustomers::CreateService).to have_received(:call)
  end
end
