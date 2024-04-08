# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:integration) { create(:netsuite_integration, organization:) }

  describe '.destroy' do
    before { integration }

    it 'destroys the integration' do
      expect { destroy_service.destroy(id: integration.id) }
        .to change(Integrations::BaseIntegration, :count).by(-1)
    end

    context 'when integration is not found' do
      it 'returns an error' do
        result = destroy_service.destroy(id: nil)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('integration_not_found')
      end
    end

    context 'when integration is not attached to the organization' do
      let(:integration) { create(:netsuite_integration) }

      it 'returns an error' do
        result = destroy_service.destroy(id: integration.id)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('integration_not_found')
      end
    end
  end
end
