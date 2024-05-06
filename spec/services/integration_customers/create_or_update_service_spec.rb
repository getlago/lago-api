# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationCustomers::CreateOrUpdateService, type: :service do
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization:) }
  let(:subsidiary_id) { '1' }
  let(:integration_customer_params) do
    {
      integration: 'netsuite',
      integration_code:,
      sync_with_provider:,
      external_customer_id:,
      subsidiary_id:,
    }
  end

  describe '#call' do
    subject(:service_call) { described_class.call(integration_customer_params:, customer:, new_customer:) }

    context 'without integration' do
      let(:integration_code) { 'not_exists' }
      let(:sync_with_provider) { true }
      let(:external_customer_id) { nil }
      let(:new_customer) { true }

      it 'does not call create job' do
        expect { service_call }.not_to have_enqueued_job(IntegrationCustomers::CreateJob)
      end

      it 'does not call update job' do
        expect { service_call }.not_to have_enqueued_job(IntegrationCustomers::UpdateJob)
      end
    end

    context 'without external fields set' do
      let(:integration_code) { integration.code }
      let(:sync_with_provider) { false }
      let(:external_customer_id) { nil }
      let(:new_customer) { true }

      it 'does not call create job' do
        expect { service_call }.not_to have_enqueued_job(IntegrationCustomers::CreateJob)
      end

      it 'does not call update job' do
        expect { service_call }.not_to have_enqueued_job(IntegrationCustomers::UpdateJob)
      end
    end

    context 'when removing integration customer' do
      let(:integration_customer) { create(:netsuite_customer, customer:, integration:) }
      let(:integration_code) { integration.code }
      let(:sync_with_provider) { true }
      let(:external_customer_id) { nil }
      let(:new_customer) { false }

      before do
        IntegrationCustomers::BaseCustomer.destroy_all

        integration_customer
      end

      it 'removes integration customer object' do
        service_call

        expect(IntegrationCustomers::BaseCustomer.count).to eq(0)
      end
    end

    context 'when creating integration customer' do
      let(:integration_code) { integration.code }
      let(:sync_with_provider) { true }
      let(:external_customer_id) { nil }
      let(:new_customer) { true }

      it 'calls create job' do
        expect { service_call }.to have_enqueued_job(IntegrationCustomers::CreateJob)
      end

      context 'with updating mode' do
        let(:new_customer) { false }

        it 'calls create job' do
          expect { service_call }.to have_enqueued_job(IntegrationCustomers::CreateJob)
        end
      end
    end

    context 'when updating integration customer' do
      let(:integration_customer) { create(:netsuite_customer, customer:, integration:) }
      let(:integration_code) { integration.code }
      let(:sync_with_provider) { true }
      let(:external_customer_id) { '12345' }
      let(:new_customer) { false }

      before { integration_customer }

      it 'calls update job' do
        expect { service_call }.to have_enqueued_job(IntegrationCustomers::UpdateJob)
      end
    end
  end
end
