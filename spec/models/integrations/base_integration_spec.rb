# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::BaseIntegration, type: :model do
  subject(:integration) { described_class.new(attributes) }

  let(:secrets) { {'api_key' => api_key, 'api_secret' => api_secret} }
  let(:api_key) { SecureRandom.uuid }
  let(:api_secret) { SecureRandom.uuid }

  let(:attributes) do
    {secrets: secrets.to_json}
  end

  it { is_expected.to have_many(:integration_mappings).dependent(:destroy) }
  it { is_expected.to have_many(:integration_collection_mappings).dependent(:destroy) }
  it { is_expected.to have_many(:integration_customers).dependent(:destroy) }
  it { is_expected.to have_many(:integration_items).dependent(:destroy) }
  it { is_expected.to have_many(:integration_resources).dependent(:destroy) }

  describe '.secrets_json' do
    it { expect(integration.secrets_json).to eq(secrets) }
  end

  describe '.push_to_secrets' do
    it 'push the value into the secrets' do
      integration.push_to_secrets(key: 'api_key', value: 'foo_bar')

      expect(integration.secrets_json).to eq(
        {
          'api_key' => 'foo_bar',
          'api_secret' => api_secret
        },
      )
    end
  end

  describe '.get_from_secrets' do
    it { expect(integration.get_from_secrets('api_secret')).to eq(api_secret) }

    it { expect(integration.get_from_secrets(nil)).to be_nil }
    it { expect(integration.get_from_secrets('foo')).to be_nil }
  end

  describe '.push_to_settings' do
    it 'push the value into the secrets' do
      integration.push_to_settings(key: 'key1', value: 'val1')

      expect(integration.settings).to eq(
        {
          'key1' => 'val1'
        },
      )
    end
  end

  describe '.get_from_settings' do
    before { integration.push_to_settings(key: 'key1', value: 'val1') }

    it { expect(integration.get_from_settings('key1')).to eq('val1') }

    it { expect(integration.get_from_settings(nil)).to be_nil }
    it { expect(integration.get_from_settings('foo')).to be_nil }
  end
end
