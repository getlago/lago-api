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

  describe '.accounting_kind' do
    let(:netsuite_customer) { create(:netsuite_customer) }
    let(:xero_customer) { create(:xero_customer) }
    let(:anrok_customer) { create(:anrok_customer) }
    let(:hubspot_customer) { create(:hubspot_customer) }

    before do
      netsuite_customer
      xero_customer
      anrok_customer
      hubspot_customer
    end

    it 'returns only accounting kind customers' do
      expect(described_class.accounting_kind).to contain_exactly(netsuite_customer, xero_customer)
    end
  end

  describe '.crm_kind' do
    let(:netsuite_customer) { create(:netsuite_customer) }
    let(:xero_customer) { create(:xero_customer) }
    let(:anrok_customer) { create(:anrok_customer) }
    let(:hubspot_customer) { create(:hubspot_customer) }

    before do
      netsuite_customer
      xero_customer
      anrok_customer
      hubspot_customer
    end

    it 'returns only crm kind customers' do
      expect(described_class.crm_kind).to contain_exactly(hubspot_customer)
    end
  end

  describe '.customer_type' do
    subject(:customer_type_call) { described_class.customer_type(type) }

    context 'when type is netsuite' do
      let(:type) { 'netsuite' }
      let(:customer_type) { 'IntegrationCustomers::NetsuiteCustomer' }

      it 'returns customer type' do
        expect(subject).to eq(customer_type)
      end
    end

    context 'when type is okta' do
      let(:type) { 'okta' }
      let(:customer_type) { 'IntegrationCustomers::OktaCustomer' }

      it 'returns customer type' do
        expect(subject).to eq(customer_type)
      end
    end

    context 'when type is anrok' do
      let(:type) { 'anrok' }
      let(:customer_type) { 'IntegrationCustomers::AnrokCustomer' }

      it 'returns customer type' do
        expect(subject).to eq(customer_type)
      end
    end

    context 'when type is xero' do
      let(:type) { 'xero' }
      let(:customer_type) { 'IntegrationCustomers::XeroCustomer' }

      it 'returns customer type' do
        expect(subject).to eq(customer_type)
      end
    end

    context 'when type is hubspot' do
      let(:type) { 'hubspot' }
      let(:customer_type) { 'IntegrationCustomers::HubspotCustomer' }

      it 'returns customer type' do
        expect(subject).to eq(customer_type)
      end
    end

    context 'when type is salesforce' do
      let(:type) { 'salesforce' }
      let(:customer_type) { 'IntegrationCustomers::SalesforceCustomer' }

      it 'returns customer type' do
        expect(subject).to eq(customer_type)
      end
    end

    context 'when type is not supported' do
      let(:type) { 'n/a' }

      it 'raises an error' do
        expect { subject }.to raise_error(NotImplementedError)
      end
    end
  end

  describe '#push_to_settings' do
    it 'push the value into settings' do
      integration_customer.push_to_settings(key: 'key1', value: 'val1')

      expect(integration_customer.settings).to eq(
        {
          'key1' => 'val1'
        }
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
