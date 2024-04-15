# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::OktaService do
  subject(:service) { described_class.new }

  let(:organization) { create(:organization) }
  let(:okta_integration) { create(:okta_integration) }

  before { okta_integration }

  describe '#authorize' do
    let(:email) { "foo@#{okta_integration.domain}" }

    it 'returns an authorize url' do
      result = service.authorize(email:)

      aggregate_failures do
        expect(result).to be_success
        expect(result.url).to include(okta_integration.organization_name.downcase)
        expect(result.url).to include(okta_integration.client_id)
      end
    end
  end

  context 'when domain is not configured with an integration' do
    let(:email) { 'foo@bar.com' }

    it 'returns a failure result' do
      result = service.authorize(email:)

      aggregate_failures do
        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include('domain_not_configured')
      end
    end
  end
end
