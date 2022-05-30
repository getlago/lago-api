# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreateEventJob, type: :job do
  let(:organization) { create(:organization) }
  let(:params) { {} }
  let(:event_service) { instance_double(EventsService) }
  let(:result) { BaseService::Result.new }
  let(:timestamp) { Time.zone.now.to_i }
  let(:metadata) { { user_agent: 'Lago Ruby v0.0.1', ip_address: '182.11.32.11' } }

  it 'calls the event service' do
    allow(EventsService).to receive(:new).and_return(event_service)
    allow(event_service).to receive(:create)
      .with(organization: organization, params: params, timestamp: timestamp, metadata: metadata)
      .and_return(result)

    described_class.perform_now(organization, params, timestamp, metadata)

    expect(EventsService).to have_received(:new)
    expect(event_service).to have_received(:create)
  end

  context 'when result is a failure' do
    let(:result) do
      BaseService::Result.new.fail!('Invalid customer id')
    end

    it 'raises an error' do
      allow(EventsService).to receive(:new).and_return(event_service)
      allow(event_service).to receive(:create)
        .with(organization: organization, params: params, timestamp: timestamp, metadata: metadata)
        .and_return(result)

      expect do
        described_class.perform_now(organization, params, timestamp, metadata)
      end.to raise_error(BaseService::FailedResult)

      expect(EventsService).to have_received(:new)
      expect(event_service).to have_received(:create)
    end
  end
end
