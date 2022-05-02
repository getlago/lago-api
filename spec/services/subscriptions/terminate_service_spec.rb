# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::TerminateService do
  subject(:terminate_service) { described_class.new }

  describe '.terminate' do
    let(:subscription) { create(:subscription) }

    it 'terminates a subscription' do
      result = terminate_service.terminate(subscription.id)

      aggregate_failures do
        expect(result.subscription).to be_present
        expect(result.subscription).to be_terminated
        expect(result.subscription.terminated_at).to be_present
      end
    end

    it 'enqueues a BillSubscriptionJob' do
      expect do
        terminate_service.terminate(subscription.id)
      end.to have_enqueued_job(BillSubscriptionJob)
    end

    context 'when subscription is not found' do
      let(:subscription) { OpenStruct.new(id: '123456') }

      it 'returns an error' do
        result = terminate_service.terminate(subscription.id)

        expect(result.error).to eq('not_found')
      end
    end
  end
end
