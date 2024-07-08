# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::UpdateService, type: :service do
  subject(:customers_service) { described_class.new(user) }

  let(:user) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:payment_provider_code) { 'stripe_1' }

  describe 'update' do
    let(:user) { membership.user }

    let(:customer) { create(:customer, organization:, payment_provider: 'stripe', payment_provider_code:) }
    let(:external_id) { SecureRandom.uuid }

    let(:update_args) do
      {
        id: customer.id,
        name: 'Updated customer name',
        tax_identification_number: '2246',
        net_payment_term: 8,
        external_id:,
        shipping_address: {
          city: 'Paris'
        }
      }
    end

    it 'updates a customer' do
      result = customers_service.update(**update_args)

      updated_customer = result.customer
      aggregate_failures do
        expect(updated_customer.name).to eq('Updated customer name')
        expect(updated_customer.tax_identification_number).to eq('2246')

        shipping_address = update_args[:shipping_address]
        expect(updated_customer.shipping_city).to eq(shipping_address[:city])
      end
    end

    context 'with premium features' do
      around { |test| lago_premium!(&test) }

      let(:update_args) do
        {
          id: customer.id,
          timezone: 'Europe/Paris',
          billing_configuration: {
            invoice_grace_period: 3
          }
        }
      end

      it 'updates a customer' do
        result = customers_service.update(**update_args)

        updated_customer = result.customer
        aggregate_failures do
          expect(updated_customer.timezone).to eq('Europe/Paris')

          billing = update_args[:billing_configuration]
          expect(updated_customer.invoice_grace_period).to eq(billing[:invoice_grace_period])
        end
      end
    end

    context 'with metadata' do
      let(:customer_metadata) { create(:customer_metadata, customer:) }
      let(:another_customer_metadata) { create(:customer_metadata, customer:, key: 'test', value: '1') }
      let(:update_args) do
        {
          id: customer.id,
          name: 'Updated customer name',
          metadata: [
            {
              id: customer_metadata.id,
              key: 'new key',
              value: 'new value',
              display_in_invoice: true
            },
            {
              key: 'Added key',
              value: 'Added value',
              display_in_invoice: true
            }
          ]
        }
      end

      before do
        customer_metadata
        another_customer_metadata
      end

      it 'updates metadata' do
        result = customers_service.update(**update_args)

        metadata_keys = result.customer.metadata.pluck(:key)
        metadata_ids = result.customer.metadata.pluck(:id)

        expect(result.customer.metadata.count).to eq(2)
        expect(metadata_keys).to eq(['new key', 'Added key'])
        expect(metadata_ids).to include(customer_metadata.id)
        expect(metadata_ids).not_to include(another_customer_metadata.id)
      end
    end

    context 'with validation error' do
      let(:external_id) { nil }

      it 'returns an error' do
        result = customers_service.update(**update_args)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:external_id]).to eq(['value_is_mandatory'])
        end
      end
    end

    context 'when attached to a subscription' do
      before do
        subscription = create(:subscription, customer:)
        customer.update!(currency: subscription.plan.amount_currency)
      end

      it 'updates only the name' do
        result = customers_service.update(**update_args)

        updated_customer = result.customer
        aggregate_failures do
          expect(updated_customer.name).to eq('Updated customer name')
          expect(updated_customer.external_id).to eq(customer.external_id)
        end
      end

      context 'when updating the currency' do
        let(:update_args) do
          {
            id: customer.id,
            currency: 'CAD'
          }
        end

        it 'fails' do
          result = customers_service.update(**update_args)

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages.keys).to include(:currency)
            expect(result.error.messages[:currency]).to include('currencies_does_not_match')
          end
        end
      end
    end

    context 'when updating payment provider' do
      let(:update_args) do
        {
          id: customer.id,
          name: 'Updated customer name',
          external_id:,
          payment_provider: 'stripe',
          payment_provider_code:
        }
      end

      before do
        create(:stripe_provider, organization: customer.organization, code: payment_provider_code)

        allow(PaymentProviderCustomers::UpdateService)
          .to receive(:call)
          .with(customer)
          .and_return(BaseService::Result.new)
      end

      it 'creates a payment provider customer' do
        result = customers_service.update(**update_args)

        expect(result).to be_success

        updated_customer = result.customer
        aggregate_failures do
          expect(updated_customer.payment_provider).to eq('stripe')
          expect(updated_customer.stripe_customer).to be_present
        end
      end

      it 'does not call payment provider customer update service' do
        customers_service.update(**update_args)
        expect(PaymentProviderCustomers::UpdateService).not_to have_received(:call).with(customer)
      end

      context 'with provider customer id' do
        let(:update_args) do
          {
            id: customer.id,
            external_id: SecureRandom.uuid,
            name: 'Foo Bar',
            organization_id: organization.id,
            payment_provider: 'stripe',
            provider_customer: {provider_customer_id: 'cus_12345'}
          }
        end

        it 'calls payment provider customer update service' do
          customers_service.update(**update_args)
          expect(PaymentProviderCustomers::UpdateService).to have_received(:call).with(customer)
        end

        it 'creates a payment provider customer' do
          result = customers_service.update(**update_args)

          aggregate_failures do
            expect(result).to be_success

            customer = result.customer
            expect(customer.id).to be_present
            expect(customer.payment_provider).to eq('stripe')
            expect(customer.stripe_customer).to be_present
            expect(customer.stripe_customer.provider_customer_id).to eq('cus_12345')
          end
        end

        context 'when removing a provider customer id' do
          let(:update_args) do
            {
              id: customer.id,
              external_id: SecureRandom.uuid,
              name: 'Foo Bar',
              organization_id: organization.id,
              payment_provider: nil,
              provider_customer: {provider_customer_id: nil}
            }
          end

          let(:stripe_customer) { create(:stripe_customer, customer:) }

          before do
            stripe_customer
            customer.update!(payment_provider: 'stripe')
          end

          it 'removes the provider customer id' do
            result = customers_service.update(**update_args)

            aggregate_failures do
              expect(result).to be_success

              customer = result.customer
              expect(customer.id).to eq(customer.id)
              expect(customer.payment_provider).to be_nil

              expect(customer.stripe_customer).to eq(stripe_customer)
              expect(customer.stripe_customer.provider_customer_id).to be_nil
            end
          end
        end
      end
    end

    context 'when partialy updating' do
      let(:stripe_customer) { create(:stripe_customer, customer:, provider_payment_methods: %w[sepa_debit]) }

      let(:update_args) do
        {
          id: customer.id,
          invoice_grace_period: 8
        }
      end

      around { |test| lago_premium!(&test) }
      before { stripe_customer }

      it 'updates only the updated args' do
        result = customers_service.update(**update_args)

        aggregate_failures do
          expect(result).to be_success
          expect(result.customer.invoice_grace_period).to eq(update_args[:invoice_grace_period])

          expect(result.customer.stripe_customer.provider_payment_methods).to eq(%w[sepa_debit])
        end
      end
    end

    context 'when updating net payment term' do
      it 'updates the net payment term of all draft invoices' do
        create(:invoice, :draft, customer:, net_payment_term: 30)
        create(:invoice, customer:, net_payment_term: 30)
        create(:invoice, :draft, customer:, net_payment_term: 30)

        result = customers_service.update(**update_args)

        aggregate_failures do
          expect(result).to be_success
          expect(result.customer.invoices.draft.pluck(:net_payment_term)).to eq([8, 8])
        end
      end
    end

    context 'when organization has eu tax management' do
      let(:eu_auto_tax_service) { instance_double(Customers::EuAutoTaxesService) }

      before do
        create(:tax, organization:, code: 'lago_eu_fr_standard', rate: 20.0)
        organization.update(eu_tax_management: true)

        allow(Customers::EuAutoTaxesService).to receive(:new).and_return(eu_auto_tax_service)
        allow(eu_auto_tax_service).to receive(:call).and_return('lago_eu_fr_standard')
      end

      it 'assigns the right tax to the customer' do
        result = customers_service.update(**update_args)

        aggregate_failures do
          expect(result).to be_success

          tax = result.customer.taxes.first
          expect(tax.code).to eq('lago_eu_fr_standard')
        end
      end
    end
  end
end
