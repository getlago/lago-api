# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::BaseProvider, type: :model do
  subject(:provider) { described_class.new(attributes) }

  let(:secrets) { {'api_key' => api_key, 'api_secret' => api_secret} }
  let(:api_key) { SecureRandom.uuid }
  let(:api_secret) { SecureRandom.uuid }

  let(:attributes) do
    {secrets: secrets.to_json}
  end

  describe '.json_secrets' do
    it { expect(provider.secrets_json).to eq(secrets) }
  end

  describe '.push_to_secrets' do
    it 'push the value into the secrets' do
      provider.push_to_secrets(key: 'api_key', value: 'foo_bar')

      expect(provider.secrets_json).to eq(
        {
          'api_key' => 'foo_bar',
          'api_secret' => api_secret
        }
      )
    end
  end

  describe '.get_from_secrets' do
    it { expect(provider.get_from_secrets('api_secret')).to eq(api_secret) }

    it { expect(provider.get_from_secrets(nil)).to be_nil }
    it { expect(provider.get_from_secrets('foo')).to be_nil }
  end
end
