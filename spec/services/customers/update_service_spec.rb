# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::UpdateService, type: :service do
  subject(:customers_service) { described_class.new(user) }

  let(:user) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'update' do
    let(:user) { membership.user }

    let(:customer) { create(:customer, organization:) }
    let(:external_id) { SecureRandom.uuid }

    let(:update_args) do
      {
        id: customer.id,
        name: 'Updated customer name',
        external_id:,
        billing_configuration: {
          vat_rate: 20,
        },
      }
    end

    it 'updates a customer' do
      result = customers_service.update(**update_args)

      updated_customer = result.customer
      aggregate_failures do
        expect(updated_customer.name).to eq('Updated customer name')

        billing = update_args[:billing_configuration]
        expect(updated_customer.vat_rate).to eq(billing[:vat_rate])
      end
    end

    context 'with premium features' do
      around { |test| lago_premium!(&test) }

      let(:update_args) do
        {
          id: customer.id,
          timezone: 'Europe/Paris',
          billing_configuration: {
            invoice_grace_period: 3,
          },
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

    context 'without billing configuration namespace' do
      let(:update_args) do
        {
          id: customer.id,
          name: 'Updated customer name',
          external_id:,
          invoice_grace_period: 3,
          vat_rate: 20,
        }
      end

      it 'updates billing information' do
        result = customers_service.update(**update_args)

        expect(result.customer.vat_rate).to eq(update_args[:vat_rate])
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
            currency: 'CAD',
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
        }
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

      context 'with provider customer id' do
        let(:update_args) do
          {
            id: customer.id,
            external_id: SecureRandom.uuid,
            name: 'Foo Bar',
            organization_id: organization.id,
            payment_provider: 'stripe',
            provider_customer: { provider_customer_id: 'cus_12345' },
          }
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
              provider_customer: { provider_customer_id: nil },
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
  end
end
