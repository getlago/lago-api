# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::NetsuiteMapping, type: :model do
  subject(:mapping) { build(:netsuite_mapping) }

  describe '#netsuite_id' do
    let(:netsuite_id) { SecureRandom.uuid }

    it 'assigns and retrieve a setting' do
      mapping.netsuite_id = netsuite_id
      expect(mapping.netsuite_id).to eq(netsuite_id)
    end
  end

  describe '#netsuite_account_code' do
    let(:netsuite_account_code) { 'netsuite-code-1' }

    it 'assigns and retrieve a setting' do
      mapping.netsuite_account_code = netsuite_account_code
      expect(mapping.netsuite_account_code).to eq(netsuite_account_code)
    end
  end

  describe '#netsuite_name' do
    let(:netsuite_name) { 'Credits and Discounts' }

    it 'assigns and retrieve a setting' do
      mapping.netsuite_name = netsuite_name
      expect(mapping.netsuite_name).to eq(netsuite_name)
    end
  end
end
