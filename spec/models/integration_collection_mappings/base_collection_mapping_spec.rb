# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationCollectionMappings::BaseCollectionMapping, type: :model do
  subject(:mapping) { described_class.new(type:, mapping_type:) }

  let(:mapping_type) { :fallback_item }
  let(:type) { 'IntegrationCollectionMappings::NetsuiteCollectionMapping' }

  it { is_expected.to belong_to(:integration) }

  describe 'validations' do
    describe 'of mapping type uniqueness' do
      let(:errors) { mapping.errors }

      context 'when it is unique in scope of integration' do
        it 'does not add an error' do
          expect(errors.where(:mapping_type, :taken)).not_to be_present
        end
      end

      context 'when it not is unique in scope of integration' do
        subject(:mapping) do
          described_class.new(integration:, type:, mapping_type:)
        end

        let(:integration) { create(:netsuite_integration) }

        before do
          described_class.create(integration:, type:, mapping_type:)
          mapping.valid?
        end

        it 'adds an error' do
          expect(errors.where(:mapping_type, :taken)).to be_present
        end
      end
    end
  end

  describe '#push_to_settings' do
    it 'push the value into settings' do
      mapping.push_to_settings(key: 'key1', value: 'val1')

      expect(mapping.settings).to eq(
        {
          'key1' => 'val1',
        },
      )
    end
  end

  describe '#get_from_settings' do
    before { mapping.push_to_settings(key: 'key1', value: 'val1') }

    it { expect(mapping.get_from_settings('key1')).to eq('val1') }

    it { expect(mapping.get_from_settings(nil)).to be_nil }
    it { expect(mapping.get_from_settings('foo')).to be_nil }
  end
end
