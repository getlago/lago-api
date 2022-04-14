# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::TerminateJob, type: :job do
  let(:subscription) { create(:subscription) }
  let(:timestamp) { Time.zone.now.to_i }

  let(:subscription_service) { instance_double(SubscriptionsService) }
  let(:result) { BaseService::Result.new }

  it 'calls the subscription service' do
    allow(SubscriptionsService).to receive(:new).and_return(subscription_service)
    allow(subscription_service).to receive(:terminate_and_start_next)
      .with(subscription: subscription, timestamp: timestamp)
      .and_return(result)

    described_class.perform_now(subscription, timestamp)

    expect(SubscriptionsService).to have_received(:new)
    expect(subscription_service).to have_received(:terminate_and_start_next)
  end

  context 'when result is a failure' do
    let(:result) do
      BaseService::Result.new.fail!('error')
    end

    it 'raises an error' do
      allow(SubscriptionsService).to receive(:new).and_return(subscription_service)
      allow(subscription_service).to receive(:terminate_and_start_next)
        .with(subscription: subscription, timestamp: timestamp)
        .and_return(result)

      expect do
        described_class.perform_now(subscription, timestamp)
      end.to raise_error(BaseService::FailedResult)

      expect(SubscriptionsService).to have_received(:new)
      expect(subscription_service).to have_received(:terminate_and_start_next)
    end
  end
end
