# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::SendRestletEndpointJob, type: :job do
  subject(:send_endpoint_job) { described_class }

  let(:send_endpoint_service) { instance_double(Integrations::Aggregator::SendRestletEndpointService) }
  let(:integration) { create(:netsuite_integration) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::SendRestletEndpointService).to receive(:new).and_return(send_endpoint_service)
    allow(send_endpoint_service).to receive(:call).and_return(result)
  end

  it 'sends restlet url to the aggregator' do
    described_class.perform_now(integration:)

    expect(Integrations::Aggregator::SendRestletEndpointService).to have_received(:new)
    expect(send_endpoint_service).to have_received(:call)
  end
end
