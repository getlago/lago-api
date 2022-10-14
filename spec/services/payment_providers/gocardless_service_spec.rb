# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::GocardlessService, type: :service do
  subject(:gocardless_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:access_code) { '1234567!abc' }
  let(:oauth_client) { instance_double(OAuth2::Client) }
  let(:auth_code_strategy) { instance_double(OAuth2::Strategy::AuthCode) }
  let(:access_token) { instance_double(OAuth2::AccessToken) }
  let(:token) { 'access_token_554' }

  before do
    allow(OAuth2::Client).to receive(:new)
      .and_return(oauth_client)
    allow(oauth_client).to receive(:auth_code)
      .and_return(auth_code_strategy)
    allow(auth_code_strategy).to receive(:get_token)
      .and_return(access_token)
    allow(access_token).to receive(:token)
      .and_return(token)
  end

  describe '.create_or_update' do
    it 'creates a gocardless provider' do
      expect do
        gocardless_service.create_or_update(
          organization: organization,
          access_code: access_code,
        )
      end.to change(PaymentProviders::GocardlessProvider, :count).by(1)
    end

    context 'when organization already have a gocardless provider' do
      let(:gocardless_provider) do
        create(:gocardless_provider, organization: organization, access_token: 'access_token_123')
      end

      before { gocardless_provider }

      it 'updates the existing provider' do
        result = gocardless_service.create_or_update(
          organization: organization,
          access_code: access_code,
        )

        expect(result).to be_success

        aggregate_failures do
          expect(result.gocardless_provider.id).to eq(gocardless_provider.id)
          expect(result.gocardless_provider.access_token).to eq('access_token_554')
        end
      end
    end

    context 'with validation error' do
      let(:token) { nil }

      it 'returns an error result' do
        result = gocardless_service.create_or_update(
          organization: organization,
          access_code: access_code,
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:access_token]).to eq(['value_is_mandatory'])
        end
      end
    end
  end
end
