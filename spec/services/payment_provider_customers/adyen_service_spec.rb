# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviderCustomers::AdyenService, type: :service do
  subject(:adyen_service) { described_class.new(adyen_customer) }

  let(:customer) { create(:customer, organization:) }
  let(:adyen_provider) { create(:adyen_provider) }
  let(:organization) { adyen_provider.organization }

  let(:adyen_customer) do
    create(:adyen_customer, customer:, provider_customer_id: nil)
  end

  describe '.create' do
    it 'creates the adyen customer' do
      allow(Adyen::Customer).to receive(:create)
        .and_return(Adyen::Customer.new(id: 'cus_123456'))

      result = adyen_service.create

      expect(Adyen::Customer).to have_received(:create)

      expect(result.adyen_customer.provider_customer_id).to eq('cus_123456')
    end

    it 'delivers a success webhook' do
      allow(Adyen::Customer).to receive(:create)
        .and_return(Adyen::Customer.new(id: 'cus_123456'))

      adyen_service.create

      expect(Adyen::Customer).to have_received(:create)

      expect(SendWebhookJob).to have_been_enqueued
        .with('customer.payment_provider_created', customer)
    end

    context 'when customer already have a adyen customer id' do
      let(:adyen_customer) do
        create(:adyen_customer, customer:, provider_customer_id: 'cus_123456')
      end

      it 'does not call adyen API' do
        allow(Adyen::Customer).to receive(:create)

        adyen_service.create

        expect(Adyen::Customer).not_to have_received(:create)
      end
    end

    context 'when failing to create the customer' do
      it 'delivers an error webhook' do
        allow(Adyen::Customer).to receive(:create)
          .and_raise(Adyen::InvalidRequestError.new('error', {}))

        expect { adyen_service.create }
          .to raise_error(Adyen::InvalidRequestError)

        expect(Adyen::Customer).to have_received(:create)

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            'customer.payment_provider_error',
            customer,
            provider_error: {
              message: 'error',
              error_code: nil,
            },
          )
      end
    end
  end

  describe '.update_payment_method' do
    subject(:adyen_service) { described_class.new }

    let(:adyen_customer) do
      create(:adyen_customer, customer:, provider_customer_id: 'cus_123456')
    end

    it 'updates the customer payment method' do
      result = adyen_service.update_payment_method(
        organization_id: organization.id,
        adyen_customer_id: adyen_customer.provider_customer_id,
        payment_method_id: 'pm_123456',
      )

      aggregate_failures do
        expect(result).to be_success
        expect(result.adyen_customer.payment_method_id).to eq('pm_123456')
      end
    end

    context 'with pending invoices' do
      let(:invoice) do
        create(
          :invoice,
          customer:,
          total_amount_cents: 200,
          currency: 'EUR',
        )
      end

      before { invoice }

      it 'enqueues jobs to reprocess the pending payment' do
        result = adyen_service.update_payment_method(
          organization_id: organization.id,
          adyen_customer_id: adyen_customer.provider_customer_id,
          payment_method_id: 'pm_123456',
        )

        aggregate_failures do
          expect(result).to be_success

          expect(Invoices::Payments::AdyenCreateJob).to have_been_enqueued
            .with(invoice)
        end
      end
    end

    context 'when customer is not found' do
      it 'returns an empty result' do
        result = adyen_service.update_payment_method(
          organization_id: organization.id,
          adyen_customer_id: 'cus_InvaLid',
          payment_method_id: 'pm_123456',
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.adyen_customer).to be_nil
        end
      end

      context 'when customer in metadata is not found' do
        it 'returns an empty response' do
          result = adyen_service.update_payment_method(
            organization_id: organization.id,
            adyen_customer_id: 'cus_InvaLid',
            payment_method_id: 'pm_123456',
            metadata: {
              lago_customer_id: SecureRandom.uuid,
            },
          )

          aggregate_failures do
            expect(result).to be_success
            expect(result.adyen_customer).to be_nil
          end
        end
      end

      context 'when customer in metadata exists' do
        it 'returns a not found error' do
          result = adyen_service.update_payment_method(
            organization_id: organization.id,
            adyen_customer_id: 'cus_InvaLid',
            payment_method_id: 'pm_123456',
            metadata: {
              lago_customer_id: customer.id,
            },
          )

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq('adyen_customer_not_found')
          end
        end
      end
    end
  end

  describe '.delete_payment_method' do
    subject(:adyen_service) { described_class.new }

    let(:payment_method_id) { 'card_12345' }

    let(:adyen_customer) do
      create(
        :adyen_customer,
        customer:,
        provider_customer_id: 'cus_123456',
        payment_method_id:,
      )
    end

    it 'removes the customer payment method' do
      result = adyen_service.delete_payment_method(
        organization_id: organization.id,
        adyen_customer_id: adyen_customer.provider_customer_id,
        payment_method_id:,
      )

      aggregate_failures do
        expect(result).to be_success
        expect(result.adyen_customer.payment_method_id).to be_nil
      end
    end

    context 'when customer payment method is not the deleted one' do
      it 'does not remove the customer payment method' do
        result = adyen_service.delete_payment_method(
          organization_id: organization.id,
          adyen_customer_id: adyen_customer.provider_customer_id,
          payment_method_id: 'other_payment_method_id',
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.adyen_customer.payment_method_id).to eq(payment_method_id)
        end
      end
    end

    context 'when customer is not found' do
      it 'returns an empty result' do
        result = adyen_service.delete_payment_method(
          organization_id: organization.id,
          adyen_customer_id: 'cus_InvaLid',
          payment_method_id: 'pm_123456',
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.adyen_customer).to be_nil
        end
      end

      context 'when customer in metadata is not found' do
        it 'returns an empty response' do
          result = adyen_service.delete_payment_method(
            organization_id: organization.id,
            adyen_customer_id: 'cus_InvaLid',
            payment_method_id: 'pm_123456',
            metadata: {
              lago_customer_id: SecureRandom.uuid,
            },
          )

          aggregate_failures do
            expect(result).to be_success
            expect(result.adyen_customer).to be_nil
          end
        end
      end

      context 'when customer in metadata exists' do
        it 'returns a not found error' do
          result = adyen_service.delete_payment_method(
            organization_id: organization.id,
            adyen_customer_id: 'cus_InvaLid',
            payment_method_id: 'pm_123456',
            metadata: {
              lago_customer_id: customer.id,
            },
          )

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq('adyen_customer_not_found')
          end
        end
      end
    end
  end

  describe '.check_payment_method' do
    let(:payment_method_id) { 'card_12345' }

    let(:adyen_customer) do
      create(
        :adyen_customer,
        customer:,
        provider_customer_id: 'cus_123456',
        payment_method_id:,
      )
    end

    let(:payment_method) { Adyen::PaymentMethod.new(id: payment_method_id) }

    let(:adyen_api_customer) { instance_double(Adyen::Customer) }

    before do
      allow(Adyen::Customer).to receive(:new)
        .and_return(adyen_api_customer)
    end

    it 'checks for the existance of the payment method' do
      allow(adyen_api_customer)
        .to receive(:retrieve_payment_method)
        .and_return(payment_method)

      result = adyen_service.check_payment_method(payment_method_id)

      aggregate_failures do
        expect(result).to be_success
        expect(result.payment_method.id).to eq(payment_method_id)

        expect(Adyen::Customer).to have_received(:new)
        expect(adyen_api_customer).to have_received(:retrieve_payment_method)
      end
    end

    context 'when payment method is not found on adyen' do
      before do
        allow(adyen_api_customer)
          .to receive(:retrieve_payment_method)
          .and_raise(Adyen::InvalidRequestError.new('error', {}))
      end

      it 'returns a failed result' do
        result = adyen_service.check_payment_method(payment_method_id)

        aggregate_failures do
          expect(result).not_to be_success

          expect(Adyen::Customer).to have_received(:new)
          expect(adyen_api_customer).to have_received(:retrieve_payment_method)
        end
      end
    end
  end
end
