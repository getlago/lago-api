# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::GoogleService do
  subject(:service) { described_class.new }

  before do
    ENV['GOOGLE_AUTH_CLIENT_ID'] = 'client_id'
    ENV['GOOGLE_AUTH_CLIENT_SECRET'] = 'client_secret'
  end

  describe '#authorize_url' do
    it 'returns the authorize url' do
      request = Rack::Request.new(Rack::MockRequest.env_for('http://example.com'))
      result = service.authorize_url(request)

      aggregate_failures do
        expect(result).to be_success
        expect(result.url).to include('https://accounts.google.com/o/oauth2/auth')
      end
    end

    context 'when google auth is not set up' do
      before do
        ENV['GOOGLE_AUTH_CLIENT_ID'] = nil
        ENV['GOOGLE_AUTH_CLIENT_SECRET'] = nil
      end

      it 'returns a service failure' do
        request = Rack::Request.new(Rack::MockRequest.env_for('http://example.com'))
        result = service.authorize_url(request)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.code).to eq('google_auth_missing_setup')
        end
      end
    end
  end

  describe '#login' do
    let(:authorizer) { instance_double(Google::Auth::UserAuthorizer) }
    let(:oidc_verifier) { instance_double(Google::Auth::IDTokens) }
    let(:authorizer_response) { instance_double(Google::Auth::UserRefreshCredentials, id_token: 'id_token') }
    let(:oidc_response) do
      { 'email' => 'foo@bar.com' }
    end

    before do
      allow(Google::Auth::UserAuthorizer).to receive(:new).and_return(authorizer)
      allow(authorizer).to receive(:get_credentials_from_code).and_return(authorizer_response)
      allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_return(oidc_response)
    end

    context 'when user exists' do
      before do
        user = create(:user, email: 'foo@bar.com', password: 'foobar')
        create(:membership, :active, user:)
      end

      it 'logins the user' do
        result = service.login('code')

        aggregate_failures do
          expect(result).to be_success
          expect(result.user).to be_a(User)
          expect(result.token).to be_present
        end
      end
    end

    context 'when user does not exist' do
      it 'returns a validation failure' do
        result = service.login('code')

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.messages.values.flatten).to include('user_does_not_exist')
        end
      end
    end

    context 'when user does not have active memberships' do
      before do
        create(:user, email: 'foo@bar.com')
      end

      it 'returns a validation failure' do
        result = service.login('code')

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.messages.values.flatten).to include('user_does_not_exist')
        end
      end
    end

    context 'when google auth is not set up' do
      before do
        ENV['GOOGLE_AUTH_CLIENT_ID'] = nil
        ENV['GOOGLE_AUTH_CLIENT_SECRET'] = nil
      end

      it 'returns a service failure' do
        result = service.login('code')

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.code).to eq('google_auth_missing_setup')
        end
      end
    end
  end
end
