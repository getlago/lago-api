# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::CustomersController, type: :request do
  describe 'create' do
    let(:organization) { stripe_provider.organization }
    let(:stripe_provider) { create(:stripe_provider) }
    let(:create_params) do
      {
        external_id: SecureRandom.uuid,
        name: 'Foo Bar',
        currency: 'EUR',
        timezone: 'America/New_York',
        external_salesforce_id: 'foobar'
      }
    end

    it 'returns a success' do
      post_with_token(organization, '/api/v1/customers', {customer: create_params})

      expect(response).to have_http_status(:success)

      aggregate_failures do
        expect(json[:customer][:lago_id]).to be_present
        expect(json[:customer][:external_id]).to eq(create_params[:external_id])
        expect(json[:customer][:name]).to eq(create_params[:name])
        expect(json[:customer][:created_at]).to be_present
        expect(json[:customer][:currency]).to eq(create_params[:currency])
        expect(json[:customer][:external_salesforce_id]).to eq(create_params[:external_salesforce_id])
      end
    end

    context 'with premium features' do
      around { |test| lago_premium!(&test) }

      let(:create_params) do
        {
          external_id: SecureRandom.uuid,
          name: 'Foo Bar',
          timezone: 'America/New_York'
        }
      end

      it 'returns a success' do
        post_with_token(organization, '/api/v1/customers', {customer: create_params})

        expect(response).to have_http_status(:success)

        aggregate_failures do
          expect(json[:customer][:timezone]).to eq(create_params[:timezone])
        end
      end
    end

    context 'with billing configuration' do
      around { |test| lago_premium!(&test) }

      let(:create_params) do
        {
          external_id: SecureRandom.uuid,
          name: 'Foo Bar',
          billing_configuration: {
            invoice_grace_period: 3,
            payment_provider: 'stripe',
            payment_provider_code: stripe_provider.code,
            provider_customer_id: 'stripe_id',
            document_locale: 'fr',
            provider_payment_methods:
          }
        }
      end

      before do
        stub_request(:post, 'https://api.stripe.com/v1/checkout/sessions')
          .to_return(status: 200, body: body.to_json, headers: {})

        allow(Stripe::Checkout::Session).to receive(:create)
          .and_return({'url' => 'https://example.com'})

        post_with_token(organization, '/api/v1/customers', {customer: create_params})
      end

      context 'when provider payment methods are not present' do
        let(:provider_payment_methods) { nil }

        it 'returns a success' do
          expect(response).to have_http_status(:success)

          expect(json[:customer][:lago_id]).to be_present
          expect(json[:customer][:external_id]).to eq(create_params[:external_id])

          billing = json[:customer][:billing_configuration]
          aggregate_failures do
            expect(billing).to be_present
            expect(billing[:payment_provider]).to eq('stripe')
            expect(billing[:payment_provider_code]).to eq(stripe_provider.code)
            expect(billing[:provider_customer_id]).to eq('stripe_id')
            expect(billing[:invoice_grace_period]).to eq(3)
            expect(billing[:document_locale]).to eq('fr')
            expect(billing[:provider_payment_methods]).to eq(%w[card])
          end
        end
      end

      context 'when both provider payment methods are set' do
        let(:provider_payment_methods) { %w[card sepa_debit] }

        it 'returns a success' do
          expect(response).to have_http_status(:success)

          expect(json[:customer][:lago_id]).to be_present
          expect(json[:customer][:external_id]).to eq(create_params[:external_id])

          billing = json[:customer][:billing_configuration]
          aggregate_failures do
            expect(billing).to be_present
            expect(billing[:payment_provider]).to eq('stripe')
            expect(billing[:payment_provider_code]).to eq(stripe_provider.code)
            expect(billing[:provider_customer_id]).to eq('stripe_id')
            expect(billing[:invoice_grace_period]).to eq(3)
            expect(billing[:document_locale]).to eq('fr')
            expect(billing[:provider_payment_methods]).to eq(%w[card sepa_debit])
          end
        end
      end

      context 'when provider payment methods contain only card' do
        let(:provider_payment_methods) { %w[card] }

        it 'returns a success' do
          expect(response).to have_http_status(:success)

          expect(json[:customer][:lago_id]).to be_present
          expect(json[:customer][:external_id]).to eq(create_params[:external_id])

          billing = json[:customer][:billing_configuration]
          aggregate_failures do
            expect(billing).to be_present
            expect(billing[:payment_provider]).to eq('stripe')
            expect(billing[:payment_provider_code]).to eq(stripe_provider.code)
            expect(billing[:provider_customer_id]).to eq('stripe_id')
            expect(billing[:invoice_grace_period]).to eq(3)
            expect(billing[:document_locale]).to eq('fr')
            expect(billing[:provider_payment_methods]).to eq(%w[card])
          end
        end
      end

      context 'when provider payment methods contain only sepa_debit' do
        let(:provider_payment_methods) { %w[sepa_debit] }

        it 'returns a success' do
          expect(response).to have_http_status(:success)

          expect(json[:customer][:lago_id]).to be_present
          expect(json[:customer][:external_id]).to eq(create_params[:external_id])

          billing = json[:customer][:billing_configuration]
          aggregate_failures do
            expect(billing).to be_present
            expect(billing[:payment_provider]).to eq('stripe')
            expect(billing[:payment_provider_code]).to eq(stripe_provider.code)
            expect(billing[:provider_customer_id]).to eq('stripe_id')
            expect(billing[:invoice_grace_period]).to eq(3)
            expect(billing[:document_locale]).to eq('fr')
            expect(billing[:provider_payment_methods]).to eq(%w[sepa_debit])
          end
        end
      end
    end

    context 'with metadata' do
      let(:create_params) do
        {
          external_id: SecureRandom.uuid,
          name: 'Foo Bar',
          metadata: [
            {
              key: 'Hello',
              value: 'Hi',
              display_in_invoice: true
            }
          ]
        }
      end

      it 'returns a success' do
        post_with_token(organization, '/api/v1/customers', {customer: create_params})

        expect(response).to have_http_status(:success)

        expect(json[:customer][:lago_id]).to be_present
        expect(json[:customer][:external_id]).to eq(create_params[:external_id])

        metadata = json[:customer][:metadata]
        aggregate_failures do
          expect(metadata).to be_present
          expect(metadata.first[:key]).to eq('Hello')
          expect(metadata.first[:value]).to eq('Hi')
          expect(metadata.first[:display_in_invoice]).to eq(true)
        end
      end
    end

    context 'with invalid params' do
      let(:create_params) do
        {name: 'Foo Bar', currency: 'invalid'}
      end

      it 'returns an unprocessable_entity' do
        post_with_token(organization, '/api/v1/customers', {customer: create_params})

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /customers/:customer_external_id/portal_url' do
    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }

    context 'when licence is premium' do
      around { |test| lago_premium!(&test) }

      it 'returns the portal url' do
        get_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/portal_url"
        )

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:customer][:portal_url]).to include('/customer-portal/')
        end
      end

      context 'when customer does not belongs to the organization' do
        let(:customer) { create(:customer) }

        it 'returns not found error' do
          get_with_token(
            organization,
            "/api/v1/customers/#{customer.external_id}/portal_url"
          )

          expect(response).to have_http_status(:not_found)
        end
      end
    end

    context 'when licence is not premium' do
      it 'returns error' do
        get_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/portal_url"
        )

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /customers' do
    let(:organization) { create(:organization) }

    before do
      create_list(:customer, 2, organization:)
    end

    it 'returns all customers from organization' do
      get_with_token(organization, '/api/v1/customers')

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(json[:meta][:total_count]).to eq(2)
        expect(json[:customers][0][:taxes]).not_to be_nil
      end
    end
  end

  describe 'GET /customers/:customer_id' do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }

    before do
      customer
    end

    it 'returns the customer' do
      get_with_token(
        organization,
        "/api/v1/customers/#{customer.external_id}"
      )

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(json[:customer][:lago_id]).to eq(customer.id)
        expect(json[:customer][:taxes]).not_to be_nil
      end
    end

    context 'with not existing external_id' do
      it 'returns a not found error' do
        get_with_token(organization, '/api/v1/customers/foobar')

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /customers/:customer_id' do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }

    before { customer }

    it 'deletes a customer' do
      expect { delete_with_token(organization, "/api/v1/customers/#{customer.external_id}") }
        .to change(Customer, :count).by(-1)
    end

    it 'returns deleted customer' do
      delete_with_token(organization, "/api/v1/customers/#{customer.external_id}")

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:customer][:lago_id]).to eq(customer.id)
        expect(json[:customer][:external_id]).to eq(customer.external_id)
      end
    end

    context 'when customer does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, '/api/v1/customers/invalid')

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /customers/:external_customer_id/checkout_url' do
    let(:organization) { create(:organization) }
    let(:stripe_provider) { create(:stripe_provider, organization:) }
    let(:customer) { create(:customer, organization:) }

    before do
      create(
        :stripe_customer,
        customer_id: customer.id,
        payment_provider: stripe_provider
      )

      customer.update(payment_provider: 'stripe', payment_provider_code: stripe_provider.code)

      allow(Stripe::Checkout::Session).to receive(:create)
        .and_return({'url' => 'https://example.com'})
    end

    it 'returns the new generated checkout url' do
      post_with_token(organization, "/api/v1/customers/#{customer.external_id}/checkout_url")

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:customer][:checkout_url]).to eq('https://example.com')
      end
    end
  end
end
