# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::UpdateService, type: :service do
  subject(:update_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:subscription) { create(:subscription) }

  describe 'update' do
    before { subscription }

    let(:update_args) do
      {
        id: subscription.id,
        name: 'new name'
      }
    end

    it 'updates the subscription' do
      result = update_service.update(**update_args)

      expect(result).to be_success

      aggregate_failures do
        expect(result.subscription.name).to eq('new name')
      end
    end

    context 'with invalid id' do
      let(:update_args) do
        {
          id: subscription.id + '123',
          name: 'new name'
        }
      end

      it 'returns an error' do
        result = update_service.update(**update_args)

        expect(result).to_not be_success
        expect(result.error_code).to eq('not_found')
      end
    end
  end
end
