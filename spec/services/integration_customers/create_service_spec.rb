# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationCustomers::CreateService, type: :service do
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization:) }

  describe '#call' do
    subject(:service_call) { described_class.call(params:, integration:, customer:) }

    let(:params) do
      {
        integration_type: 'netsuite',
        integration_code:,
        sync_with_provider:,
        external_customer_id:,
        subsidiary_id:,
      }
    end

    let(:subsidiary_id) { '1' }

    context 'with netsuite premium integration present' do
      let(:integration_code) { integration.code }
      let(:external_customer_id) { nil }
      let(:sync_with_provider) { true }
      let(:contact_id) { SecureRandom.uuid }

      let(:create_result) do
        result = BaseService::Result.new
        result.contact_id = contact_id
        result
      end

      let(:aggregator_contacts_create_service) do
        instance_double(Integrations::Aggregator::Contacts::CreateService)
      end

      let(:integration_customer) { IntegrationCustomers::BaseCustomer.last }

      around { |test| lago_premium!(&test) }

      before do
        organization.update!(premium_integrations: ['netsuite'])

        allow(Integrations::Aggregator::Contacts::CreateService)
          .to receive(:new).and_return(aggregator_contacts_create_service)

        allow(aggregator_contacts_create_service).to receive(:call).and_return(create_result)
      end

      context 'when sync with provider is true' do
        let(:sync_with_provider) { true }

        context 'when customer external id is present' do
          let(:external_customer_id) { SecureRandom.uuid }

          it 'returns integration customer' do
            result = service_call

            aggregate_failures do
              expect(aggregator_contacts_create_service).not_to have_received(:call)
              expect(result).to be_success
              expect(result.integration_customer).to eq(integration_customer)
              expect(result.integration_customer.external_customer_id).to eq(external_customer_id)
            end
          end

          it 'creates integration customer' do
            expect { service_call }.to change(IntegrationCustomers::BaseCustomer, :count).by(1)
          end
        end

        context 'when customer external id is not present' do
          let(:external_customer_id) { nil }

          it 'returns integration customer' do
            result = service_call

            aggregate_failures do
              expect(aggregator_contacts_create_service).to have_received(:call)
              expect(result).to be_success
              expect(result.integration_customer).to eq(integration_customer)
            end
          end

          it 'creates integration customer' do
            expect { service_call }.to change(IntegrationCustomers::BaseCustomer, :count).by(1)
          end
        end
      end

      context 'when sync with provider is false' do
        let(:sync_with_provider) { false }

        context 'when customer external id is present' do
          let(:external_customer_id) { SecureRandom.uuid }

          it 'does not calls aggregator create service' do
            service_call

            expect(aggregator_contacts_create_service).not_to have_received(:call)
          end

          it 'creates integration customer' do
            expect { service_call }.to change(IntegrationCustomers::BaseCustomer, :count).by(1)
          end
        end

        context 'when customer external id is not present' do
          let(:external_customer_id) { nil }

          it 'does not calls aggregator create service' do
            service_call

            expect(aggregator_contacts_create_service).not_to have_received(:call)
          end

          it 'does not create integration customer' do
            expect { service_call }.not_to change(IntegrationCustomers::BaseCustomer, :count)
          end
        end
      end
    end
  end
end
