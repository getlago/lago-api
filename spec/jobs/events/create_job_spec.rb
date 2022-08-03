# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::CreateJob, type: :job do
  let(:organization) { create(:organization) }
  let(:params) { {} }
  let(:create_service) { instance_double(Events::CreateService) }
  let(:result) { BaseService::Result.new }
  let(:timestamp) { Time.zone.now.to_i }
  let(:metadata) { { user_agent: 'Lago Ruby v0.0.1', ip_address: '182.11.32.11' } }

  it 'calls the event service' do
    allow(Events::CreateService).to receive(:new).and_return(create_service)
    allow(create_service).to receive(:call)
      .with(organization: organization, params: params, timestamp: Time.zone.at(timestamp), metadata: metadata)
      .and_return(result)

    described_class.perform_now(organization, params, timestamp, metadata)

    expect(Events::CreateService).to have_received(:new)
    expect(create_service).to have_received(:call)
  end

  context 'when result is a failure' do
    let(:result) do
      BaseService::Result.new.fail!(code: 'Invalid customer id')
    end

    it 'raises an error' do
      allow(Events::CreateService).to receive(:new).and_return(create_service)
      allow(create_service).to receive(:call)
        .with(organization: organization, params: params, timestamp: Time.zone.at(timestamp), metadata: metadata)
        .and_return(result)

      expect do
        described_class.perform_now(organization, params, timestamp, metadata)
      end.to raise_error(BaseService::FailedResult)

      expect(Events::CreateService).to have_received(:new)
      expect(create_service).to have_received(:call)
    end
  end
end
