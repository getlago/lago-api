# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::NetsuiteIntegration, type: :model do
  subject(:netsuite_integration) { build(:netsuite_integration) }

  it { is_expected.to validate_presence_of(:name) }

  describe 'validations' do
    it 'validates uniqueness of the code' do
      expect(netsuite_integration).to validate_uniqueness_of(:code).scoped_to(:organization_id)
    end
  end

  describe '.connection_id' do
    it 'assigns and retrieve a secret pair' do
      netsuite_integration.connection_id = 'connection_id'
      expect(netsuite_integration.connection_id).to eq('connection_id')
    end
  end

  describe '.client_secret' do
    it 'assigns and retrieve a secret pair' do
      netsuite_integration.client_secret = 'client_secret'
      expect(netsuite_integration.client_secret).to eq('client_secret')
    end
  end

  describe 'account_id' do
    it 'assigns and retrieve a setting' do
      netsuite_integration.account_id = 'account_id'
      expect(netsuite_integration.account_id).to eq('account_id')
    end
  end

  describe '.client_id' do
    it 'assigns and retrieve a setting' do
      netsuite_integration.client_id = 'client_id'
      expect(netsuite_integration.client_id).to eq('client_id')
    end
  end
end
