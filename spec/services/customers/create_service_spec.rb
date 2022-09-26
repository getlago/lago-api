# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::CreateService, type: :service do
  subject(:customers_service) { described_class.new(user) }

  let(:user) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'create_from_api' do
    let(:create_args) do
      {
        external_id: SecureRandom.uuid,
        name: 'Foo Bar',
        currency: 'EUR',
      }
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates a new customer' do
      result = customers_service.create_from_api(
        organization: organization,
        params: create_args,
      )

      expect(result).to be_success

      customer = result.customer
      expect(customer.id).to be_present
      expect(customer.organization_id).to eq(organization.id)
      expect(customer.external_id).to eq(create_args[:external_id])
      expect(customer.name).to eq(create_args[:name])
      expect(customer.currency).to eq(create_args[:currency])
    end

    it 'calls SegmentTrackJob' do
      customer = customers_service.create_from_api(
        organization: organization,
        params: create_args,
      ).customer

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'customer_created',
        properties: {
          customer_id: customer.id,
          created_at: customer.created_at,
          payment_provider: customer.payment_provider,
          organization_id: customer.organization_id,
        },
      )
    end

    context 'when customer already exists' do
      let!(:customer) do
        create(
          :customer,
          organization: organization,
          external_id: create_args[:external_id],
          email: 'foo@bar.com',
        )
      end

      it 'updates the customer' do
        result = customers_service.create_from_api(
          organization: organization,
          params: create_args,
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.customer).to eq(customer)
          expect(result.customer.name).to eq(create_args[:name])
          expect(result.customer.external_id).to eq(create_args[:external_id])

          # NOTE: It should not erase exsting properties
          expect(result.customer.country).to eq(customer.country)
          expect(result.customer.address_line1).to eq(customer.address_line1)
          expect(result.customer.address_line2).to eq(customer.address_line2)
          expect(result.customer.state).to eq(customer.state)
          expect(result.customer.zipcode).to eq(customer.zipcode)
          expect(result.customer.email).to eq(customer.email)
          expect(result.customer.city).to eq(customer.city)
          expect(result.customer.url).to eq(customer.url)
          expect(result.customer.phone).to eq(customer.phone)
          expect(result.customer.logo_url).to eq(customer.logo_url)
          expect(result.customer.legal_name).to eq(customer.legal_name)
          expect(result.customer.legal_number).to eq(customer.legal_number)
        end
      end

      context 'when attached to a subscription' do
        let(:create_args) do
          {
            external_id: SecureRandom.uuid,
            name: 'Foo Bar',
            currency: 'CAD',
          }
        end

        before do
          subscription = create(:subscription, customer: customer)
          customer.update!(currency: subscription.plan.amount_currency)
        end

        it 'fails is we change the subscription' do
          result = customers_service.create_from_api(
            organization: organization,
            params: create_args,
          )

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages.keys).to include(:currency)
            expect(result.error.messages[:currency]).to include('currencies_does_not_match')
          end
        end
      end
    end

    context 'with validation error' do
      let(:create_args) do
        {
          name: 'Foo Bar',
        }
      end

      it 'return a failed result' do
        result = customers_service.create_from_api(
          organization: organization,
          params: create_args,
        )

        expect(result).not_to be_success
      end
    end

    context 'with stripe configuration' do
      let(:create_args) do
        {
          external_id: SecureRandom.uuid,
          name: 'Foo Bar',
          billing_configuration: {
            payment_provider: 'stripe',
            provider_customer_id: 'stripe_id',
          },
        }
      end

      it 'creates a stripe customer' do
        result = customers_service.create_from_api(
          organization: organization,
          params: create_args,
        )

        expect(result).to be_success

        aggregate_failures do
          customer = result.customer
          expect(customer.id).to be_present
          expect(customer.payment_provider).to eq('stripe')

          expect(customer.stripe_customer).to be_present

          stripe_customer = customer.stripe_customer
          expect(stripe_customer.id).to be_present
          expect(stripe_customer.provider_customer_id).to eq('stripe_id')
        end
      end
    end

    context 'with unknown payment provider' do
      let(:create_args) do
        {
          external_id: SecureRandom.uuid,
          name: 'Foo Bar',
          billing_configuration: {
            payment_provider: 'foo',
          },
        }
      end

      it 'does not create a payment provider customer' do
        result = customers_service.create_from_api(
          organization: organization,
          params: create_args,
        )

        expect(result).to be_success

        aggregate_failures do
          customer = result.customer
          expect(customer.id).to be_present
          expect(customer.payment_provider).to be_nil
          expect(customer.stripe_customer).to be_nil
        end
      end
    end

    context 'when forcing customer creation on stripe' do
      before do
        create(
          :stripe_provider,
          organization: organization,
          create_customers: true,
        )
      end

      it 'creates a payment provider customer' do
        result = customers_service.create_from_api(
          organization: organization,
          params: create_args,
        )

        aggregate_failures do
          expect(result).to be_success

          customer = result.customer
          expect(customer.id).to be_present
          expect(customer.payment_provider).to eq('stripe')
          expect(customer.stripe_customer).to be_present
        end
      end

      context 'when customer is updated' do
        before do
          create(
            :customer,
            organization: organization,
            external_id: create_args[:external_id],
            email: 'foo@bar.com',
          )
        end

        it 'does not create a payment provider customer' do
          result = customers_service.create_from_api(
            organization: organization,
            params: create_args,
          )

          aggregate_failures do
            expect(result).to be_success

            customer = result.customer
            expect(customer.id).to be_present
            expect(customer.payment_provider).to be_nil
            expect(customer.stripe_customer).not_to be_present
          end
        end
      end
    end
  end

  describe 'create' do
    let(:create_args) do
      {
        external_id: SecureRandom.uuid,
        name: 'Foo Bar',
        organization_id: organization.id,
        currency: 'EUR',
      }
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates a new customer' do
      result = customers_service.create(**create_args)

      aggregate_failures do
        expect(result).to be_success

        customer = result.customer
        expect(customer.id).to be_present
        expect(customer.organization_id).to eq(organization.id)
        expect(customer.external_id).to eq(create_args[:external_id])
        expect(customer.name).to eq(create_args[:name])
        expect(customer.currency).to eq('EUR')
      end
    end

    it 'calls SegmentTrackJob' do
      customer = customers_service.create(**create_args).customer

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'customer_created',
        properties: {
          customer_id: customer.id,
          created_at: customer.created_at,
          payment_provider: customer.payment_provider,
          organization_id: customer.organization_id,
        },
      )
    end

    context 'when customer already exists' do
      let(:customer) do
        create(:customer, organization: organization, external_id: create_args[:external_id])
      end

      before { customer }

      it 'return a failed result' do
        result = customers_service.create(**create_args)

        expect(result).not_to be_success
      end
    end

    context 'with validation error' do
      let(:create_args) do
        {
          name: 'Foo Bar',
        }
      end

      it 'return a failed result' do
        result = customers_service.create(**create_args)

        expect(result).not_to be_success
      end
    end

    context 'with payment provider' do
      before do
        create(
          :stripe_provider,
          organization: organization,
          create_customers: true,
        )
      end

      it 'creates a payment provider customer' do
        result = customers_service.create(**create_args)

        aggregate_failures do
          expect(result).to be_success

          customer = result.customer
          expect(customer.id).to be_present
          expect(customer.payment_provider).to eq('stripe')
          expect(customer.stripe_customer).to be_present
        end
      end

      context 'with provider customer id' do
        let(:create_args) do
          {
            external_id: SecureRandom.uuid,
            name: 'Foo Bar',
            organization_id: organization.id,
            payment_provider: 'stripe',
            stripe_customer: { provider_customer_id: 'cus_12345' },
          }
        end

        it 'creates a payment provider customer' do
          result = customers_service.create(**create_args)

          aggregate_failures do
            expect(result).to be_success

            customer = result.customer
            expect(customer.id).to be_present
            expect(customer.payment_provider).to eq('stripe')
            expect(customer.stripe_customer).to be_present
            expect(customer.stripe_customer.provider_customer_id).to eq('cus_12345')
          end
        end
      end
    end
  end
end
