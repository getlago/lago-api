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
      }
    end

    it 'returns a success' do
      post_with_token(organization, '/api/v1/customers', { customer: create_params })

      expect(response).to have_http_status(:success)

      aggregate_failures do
        expect(json[:customer][:lago_id]).to be_present
        expect(json[:customer][:external_id]).to eq(create_params[:external_id])
        expect(json[:customer][:name]).to eq(create_params[:name])
        expect(json[:customer][:created_at]).to be_present
        expect(json[:customer][:currency]).to eq(create_params[:currency])
      end
    end

    context 'with premium features' do
      around { |test| lago_premium!(&test) }

      let(:create_params) do
        {
          external_id: SecureRandom.uuid,
          name: 'Foo Bar',
          timezone: 'America/New_York',
        }
      end

      it 'returns a success' do
        post_with_token(organization, '/api/v1/customers', { customer: create_params })

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
            provider_customer_id: 'stripe_id',
            vat_rate: 20,
            document_locale: 'fr',
            provider_payment_methods:,
          },
        }
      end

      before do
        stub_request(:post, 'https://api.stripe.com/v1/checkout/sessions')
          .to_return(status: 200, body: body.to_json, headers: {})

        allow(Stripe::Checkout::Session).to receive(:create)
          .and_return({ 'url' => 'https://example.com' })

        post_with_token(organization, '/api/v1/customers', { customer: create_params })
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
            expect(billing[:provider_customer_id]).to eq('stripe_id')
            expect(billing[:invoice_grace_period]).to eq(3)
            expect(billing[:vat_rate]).to eq(20)
            expect(billing[:document_locale]).to eq('fr')
            expect(billing[:provider_payment_methods]).to eq(%w[card sepa_debit])
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
            expect(billing[:provider_customer_id]).to eq('stripe_id')
            expect(billing[:invoice_grace_period]).to eq(3)
            expect(billing[:vat_rate]).to eq(20)
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
            expect(billing[:provider_customer_id]).to eq('stripe_id')
            expect(billing[:invoice_grace_period]).to eq(3)
            expect(billing[:vat_rate]).to eq(20)
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
            expect(billing[:provider_customer_id]).to eq('stripe_id')
            expect(billing[:invoice_grace_period]).to eq(3)
            expect(billing[:vat_rate]).to eq(20)
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
              display_in_invoice: true,
            },
          ],
        }
      end

      it 'returns a success' do
        post_with_token(organization, '/api/v1/customers', { customer: create_params })

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
        { name: 'Foo Bar', currency: 'invalid' }
      end

      it 'returns an unprocessable_entity' do
        post_with_token(organization, '/api/v1/customers', { customer: create_params })

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /customers/:customer_id/current_usage' do
    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }
    let(:tax) { create(:tax, organization:, rate: 20) }
    let(:subscription) do
      create(
        :subscription,
        plan:,
        customer:,
        started_at: Time.zone.now - 2.years,
      )
    end
    let(:plan) { create(:plan, interval: 'monthly') }

    let(:metric) { create(:billable_metric, aggregation_type: 'count_agg') }
    let(:charge) do
      create(
        :graduated_charge,
        plan: subscription.plan,
        charge_model: 'graduated',
        billable_metric: metric,
        properties: {
          graduated_ranges: [
            {
              from_value: 0,
              to_value: nil,
              per_unit_amount: '0.01',
              flat_amount: '0.01',
            },
          ],
        },
      )
    end

    before do
      subscription
      charge
      tax

      create_list(
        :event,
        4,
        organization:,
        customer:,
        subscription:,
        code: metric.code,
        timestamp: Time.zone.now,
      )
    end

    it 'returns the usage for the customer' do
      get_with_token(
        organization,
        "/api/v1/customers/#{customer.external_id}/current_usage?external_subscription_id=#{subscription.external_id}",
      )

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:customer_usage][:from_date]).to eq(Time.zone.today.beginning_of_month.iso8601)
        expect(json[:customer_usage][:to_date]).to eq(Time.zone.today.end_of_month.iso8601)
        expect(json[:customer_usage][:issuing_date]).to eq(Time.zone.today.end_of_month.iso8601)
        expect(json[:customer_usage][:amount_cents]).to eq(5)
        expect(json[:customer_usage][:amount_currency]).to eq('EUR')
        expect(json[:customer_usage][:total_amount_cents]).to eq(6)
        expect(json[:customer_usage][:total_amount_currency]).to eq('EUR')
        expect(json[:customer_usage][:vat_amount_cents]).to eq(1)
        expect(json[:customer_usage][:vat_amount_currency]).to eq('EUR')

        charge_usage = json[:customer_usage][:charges_usage].first
        expect(charge_usage[:billable_metric][:name]).to eq(metric.name)
        expect(charge_usage[:billable_metric][:code]).to eq(metric.code)
        expect(charge_usage[:billable_metric][:aggregation_type]).to eq('count_agg')
        expect(charge_usage[:charge][:charge_model]).to eq('graduated')
        expect(charge_usage[:units]).to eq('4.0')
        expect(charge_usage[:amount_cents]).to eq(5)
        expect(charge_usage[:amount_currency]).to eq('EUR')
        expect(charge_usage[:groups]).to eq([])
      end
    end

    context 'with one dimension group' do
      let(:aws) { create(:group, billable_metric: metric, key: 'cloud', value: 'aws') }
      let(:google) { create(:group, billable_metric: metric, key: 'cloud', value: 'google') }
      let(:charge) do
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric: metric,
          properties: {},
          group_properties: [
            build(
              :group_property,
              group: aws,
              values: { amount: '10', amount_currency: 'EUR' },
            ),
            build(
              :group_property,
              group: google,
              values: { amount: '20', amount_currency: 'EUR' },
            ),
          ],
        )
      end

      before do
        create_list(
          :event,
          3,
          organization:,
          customer:,
          subscription:,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: { cloud: 'aws' },
        )

        create(
          :event,
          organization:,
          customer:,
          subscription:,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: { cloud: 'google' },
        )
      end

      it 'returns the group usage for the customer' do
        get_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/current_usage?external_subscription_id=#{subscription.external_id}",
        )

        charge_usage = json[:customer_usage][:charges_usage].first
        groups_usage = charge_usage[:groups]

        aggregate_failures do
          expect(charge_usage[:units]).to eq('4.0')
          expect(charge_usage[:amount_cents]).to eq(5000)
          expect(groups_usage).to contain_exactly(
            {
              lago_id: aws.id,
              key: nil,
              value: 'aws',
              units: '3.0',
              amount_cents: 3000,
            },
            { lago_id: google.id, key: nil, value: 'google', units: '1.0', amount_cents: 2000 },
          )
        end
      end
    end

    context 'with two dimensions group' do
      let(:aws) { create(:group, billable_metric: metric, key: 'cloud', value: 'aws') }
      let(:google) { create(:group, billable_metric: metric, key: 'cloud', value: 'google') }
      let(:aws_usa) { create(:group, billable_metric: metric, key: 'region', value: 'usa', parent_group_id: aws.id) }
      let(:aws_france) do
        create(:group, billable_metric: metric, key: 'region', value: 'france', parent_group_id: aws.id)
      end
      let(:google_usa) do
        create(:group, billable_metric: metric, key: 'region', value: 'usa', parent_group_id: google.id)
      end

      let(:charge) do
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric: metric,
          properties: {},
          group_properties: [
            build(
              :group_property,
              group: aws_usa,
              values: { amount: '10', amount_currency: 'EUR' },
            ),
            build(
              :group_property,
              group: aws_france,
              values: { amount: '20', amount_currency: 'EUR' },
            ),
            build(
              :group_property,
              group: google_usa,
              values: { amount: '30', amount_currency: 'EUR' },
            ),
          ],
        )
      end

      before do
        create_list(
          :event,
          2,
          organization:,
          customer:,
          subscription:,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: { cloud: 'aws', region: 'usa' },
        )

        create(
          :event,
          organization:,
          customer:,
          subscription:,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: { cloud: 'aws', region: 'france' },
        )

        create(
          :event,
          organization:,
          customer:,
          subscription:,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: { cloud: 'google', region: 'usa' },
        )
      end

      it 'returns the group usage for the customer' do
        get_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/current_usage?external_subscription_id=#{subscription.external_id}",
        )

        charge_usage = json[:customer_usage][:charges_usage].first
        groups_usage = charge_usage[:groups]

        aggregate_failures do
          expect(charge_usage[:units]).to eq('4.0')
          expect(charge_usage[:amount_cents]).to eq(7000)
          expect(groups_usage).to contain_exactly(
            {
              lago_id: aws_usa.id,
              key: 'aws',
              value: 'usa',
              units: '2.0',
              amount_cents: 2000,
            },
            { lago_id: aws_france.id, key: 'aws', value: 'france', units: '1.0', amount_cents: 2000 },
            { lago_id: google_usa.id, key: 'google', value: 'usa', units: '1.0', amount_cents: 3000 },
          )
        end
      end
    end

    context 'when customer does not belongs to the organization' do
      let(:customer) { create(:customer) }

      it 'returns not found' do
        get_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/current_usage?external_subscription_id=#{subscription.external_id}",
        )

        expect(response).to have_http_status(:not_found)
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
          "/api/v1/customers/#{customer.external_id}/portal_url",
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
            "/api/v1/customers/#{customer.external_id}/portal_url",
          )

          expect(response).to have_http_status(:not_found)
        end
      end
    end

    context 'when licence is not premium' do
      it 'returns error' do
        get_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/portal_url",
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
        "/api/v1/customers/#{customer.external_id}",
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
end
