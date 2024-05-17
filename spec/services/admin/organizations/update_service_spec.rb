# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Organizations::UpdateService do
  subject(:update_service) { described_class.new(organization:, params:) }

  let(:organization) { create(:organization) }

  let(:params) do
    {
      name: 'FooBar'
    }
  end

  describe '#call' do
    it 'updates the organization' do
      result = update_service.call

      aggregate_failures do
        expect(result.organization.name).to eq('FooBar')
        expect(organization.reload.name).to eq('FooBar')
      end
    end

    context 'when organization is nil' do
      let(:organization) { nil }

      it 'returns a not found error' do
        result = update_service.call

        aggregate_failures do
          expect(result.success).to be_falsey
          expect(result.error).to be_a(BaseService::NotFoundFailure)
        end
      end
    end
  end
end
