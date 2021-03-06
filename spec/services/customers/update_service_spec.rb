# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::UpdateService, type: :service do
  subject(:customers_service) { described_class.new(user) }

  let(:user) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'update' do
    let(:user) { membership.user }

    let(:customer) { create(:customer, organization: organization) }
    let(:customer_id) { SecureRandom.uuid }

    let(:update_args) do
      {
        id: customer.id,
        name: 'Updated customer name',
        customer_id: customer_id,
      }
    end

    it 'updates a customer' do
      result = customers_service.update(**update_args)

      updated_customer = result.customer
      aggregate_failures do
        expect(updated_customer.name).to eq('Updated customer name')
      end
    end

    context 'with validation error' do
      let(:customer_id) { nil }

      it 'returns an error' do
        result = customers_service.update(**update_args)

        expect(result).not_to be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end

    context 'when attached to a subscription' do
      before do
        create(:subscription, customer: customer)
      end

      it 'updates only the name' do
        result = customers_service.update(**update_args)

        updated_customer = result.customer
        aggregate_failures do
          expect(updated_customer.name).to eq('Updated customer name')
          expect(updated_customer.customer_id).to eq(customer.customer_id)
        end
      end
    end

    context 'when updating payment provider' do
      let(:update_args) do
        {
          id: customer.id,
          name: 'Updated customer name',
          customer_id: customer_id,
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
            customer_id: SecureRandom.uuid,
            name: 'Foo Bar',
            organization_id: organization.id,
            payment_provider: 'stripe',
            stripe_customer: { provider_customer_id: 'cus_12345' },
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
              customer_id: SecureRandom.uuid,
              name: 'Foo Bar',
              organization_id: organization.id,
              payment_provider: nil,
              stripe_customer: { provider_customer_id: nil },
            }
          end

          let(:stripe_customer) { create(:stripe_customer, customer: customer) }

          before { stripe_customer }

          it 'removes the provider customer id' do
            result = customers_service.update(**update_args)

            aggregate_failures do
              expect(result).to be_success

              customer = result.customer
              expect(customer.id).to eq(customer.id)
              expect(customer.payment_provider).to be_nil

              customer.stripe_customer.reload
              expect(customer.stripe_customer).to eq(stripe_customer)
              expect(customer.stripe_customer.provider_customer_id).to be_nil
            end
          end
        end
      end
    end
  end
end
