# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Subscriptions::Crm::CreateCustomerAssociationJob, type: :job do
  subject(:create_job) { described_class }

  let(:service) { instance_double(Integrations::Aggregator::Subscriptions::Crm::CreateCustomerAssociationService) }
  let(:subscription) { create(:subscription) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::Subscriptions::Crm::CreateCustomerAssociationService)
      .to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return(result)
  end

  it 'calls the aggregator create subscription crm service' do
    described_class.perform_now(subscription:)

    aggregate_failures do
      expect(Integrations::Aggregator::Subscriptions::Crm::CreateCustomerAssociationService).to have_received(:new)
      expect(service).to have_received(:call)
    end
  end
end
