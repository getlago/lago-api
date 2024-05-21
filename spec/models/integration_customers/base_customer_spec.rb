# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationCustomers::BaseCustomer, type: :model do
  subject(:integration_customer) { described_class.new(integration:, customer:, type:, external_customer_id:) }

  let(:integration) { create(:netsuite_integration) }
  let(:type) { 'IntegrationCustomers::NetsuiteCustomer' }
  let(:customer) { create(:customer) }
  let(:external_customer_id) { '123' }

  it { is_expected.to belong_to(:integration) }
  it { is_expected.to belong_to(:customer) }

  describe '#push_to_settings' do
    it 'push the value into settings' do
      integration_customer.push_to_settings(key: 'key1', value: 'val1')

      expect(integration_customer.settings).to eq(
        {
          'key1' => 'val1'
        },
      )
    end
  end

  describe '#get_from_settings' do
    before { integration_customer.push_to_settings(key: 'key1', value: 'val1') }

    it { expect(integration_customer.get_from_settings('key1')).to eq('val1') }

    it { expect(integration_customer.get_from_settings(nil)).to be_nil }
    it { expect(integration_customer.get_from_settings('foo')).to be_nil }
  end

  describe '#sync_with_provider' do
    it 'assigns and retrieve a setting' do
      integration_customer.sync_with_provider = true
      expect(integration_customer.sync_with_provider).to eq(true)
    end
  end

  describe 'validations' do
    describe 'of customer id uniqueness' do
      let(:errors) { another_integration_customer.errors }

      context 'when it is unique in scope of type' do
        subject(:another_integration_customer) do
          described_class.new(integration: another_integration, customer:, type:, external_customer_id:)
        end

        let(:another_integration) { create(:netsuite_integration) }

        before { another_integration_customer.valid? }

        it 'does not add an error' do
          expect(errors.where(:customer_id, :taken)).not_to be_present
        end
      end

      context 'when it not is unique in scope of type' do
        subject(:another_integration_customer) do
          described_class.new(integration:, customer:, type:, external_customer_id:)
        end

        before do
          described_class.create(integration:, customer:, type:, external_customer_id:)
          another_integration_customer.valid?
        end

        it 'adds an error' do
          expect(errors.where(:customer_id, :taken)).to be_present
        end
      end
    end
  end
end
