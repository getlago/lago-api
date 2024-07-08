# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::SubscriptionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 500, description: 'desc') }
  let(:commitment_invoice_display_name) { 'Overriden minimum commitment name' }
  let(:commitment_amount_cents) { 1234 }

  around { |test| lago_premium!(&test) }

  describe 'create' do
    let(:subscription_at) { Time.current.iso8601 }
    let(:ending_at) { (Time.current + 1.year).iso8601 }
    let(:plan_code) { plan.code }

    let(:params) do
      {
        external_customer_id: customer.external_id,
        plan_code:,
        name: 'subscription name',
        external_id: SecureRandom.uuid,
        billing_time: 'anniversary',
        subscription_at:,
        ending_at:,
        plan_overrides: {
          amount_cents: 100,
          name: 'overridden name',
          minimum_commitment: {
            invoice_display_name: commitment_invoice_display_name,
            amount_cents: commitment_amount_cents
          }
        }
      }
    end

    it 'returns a success', :aggregate_failures do
      create(:plan, code: plan.code, parent_id: plan.id, organization:, description: 'foo')

      freeze_time do
        post_with_token(organization, '/api/v1/subscriptions', {subscription: params})
        expect(response).to have_http_status(:ok)
        expect(json[:subscription]).to include(
          lago_id: String,
          external_id: String,
          external_customer_id: customer.external_id,
          lago_customer_id: customer.id,
          plan_code: plan.code,
          status: 'active',
          name: 'subscription name',
          started_at: String,
          billing_time: 'anniversary',
          subscription_at: Time.current.iso8601,
          ending_at: (Time.current + 1.year).iso8601,
          previous_plan_code: nil,
          next_plan_code: nil,
          downgrade_plan_date: nil
        )
        expect(json[:subscription][:plan]).to include(
          amount_cents: 100,
          name: 'overridden name',
          description: 'desc'
        )
        expect(json[:subscription][:plan][:minimum_commitment]).to include(
          invoice_display_name: commitment_invoice_display_name,
          amount_cents: commitment_amount_cents
        )
      end
    end

    context 'with external_customer_id, external_id and name as integer' do
      let(:params) do
        {
          external_customer_id: 123,
          plan_code:,
          name: 456,
          external_id: 789
        }
      end

      it 'returns a success' do
        post_with_token(organization, '/api/v1/subscriptions', {subscription: params})

        expect(response).to have_http_status(:ok)
        expect(json[:subscription]).to include(
          lago_id: String,
          external_customer_id: '123',
          name: '456',
          external_id: '789'
        )
      end
    end

    context 'without external_customer_id', :aggregate_failures do
      let(:params) do
        {
          plan_code:,
          name: 'subscription name',
          external_id: SecureRandom.uuid
        }
      end

      it 'returns an unprocessable_entity error' do
        post_with_token(organization, '/api/v1/subscriptions', {subscription: params})

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details]).to eq({external_customer_id: %w[value_is_mandatory]})
      end
    end

    context 'with invalid plan code' do
      let(:plan_code) { "#{plan.code}-invalid" }

      it 'returns a not_found error' do
        post_with_token(organization, '/api/v1/subscriptions', {subscription: params})

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with invalid subscription_at' do
      let(:subscription_at) { 'hello' }

      it 'returns an unprocessable_entity error' do
        post_with_token(organization, '/api/v1/subscriptions', {subscription: params})

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with legacy subscription_date' do
      let(:params) do
        {
          external_customer_id: customer.external_id,
          plan_code:,
          name: 'subscription name',
          external_id: SecureRandom.uuid,
          billing_time: 'anniversary',
          subscription_at: subscription_at
        }
      end

      it 'returns a success' do
        post_with_token(organization, '/api/v1/subscriptions', {subscription: params})

        expect(response).to have_http_status(:ok)

        expect(json[:subscription][:lago_id]).to be_present
        expect(json[:subscription][:external_id]).to be_present
        expect(json[:subscription][:external_customer_id]).to eq(customer.external_id)
        expect(json[:subscription][:lago_customer_id]).to eq(customer.id)
        expect(json[:subscription][:plan_code]).to eq(plan.code)
        expect(json[:subscription][:status]).to eq('active')
        expect(json[:subscription][:name]).to eq('subscription name')
        expect(json[:subscription][:started_at]).to be_present
        expect(json[:subscription][:billing_time]).to eq('anniversary')
        expect(json[:subscription][:subscription_at]).to eq(Time.zone.parse(subscription_at).iso8601)
        expect(json[:subscription][:previous_plan_code]).to be_nil
        expect(json[:subscription][:next_plan_code]).to be_nil
        expect(json[:subscription][:downgrade_plan_date]).to be_nil
      end
    end
  end

  describe 'delete /subscriptions/:id' do
    let(:subscription) { create(:subscription, customer:, plan:) }

    before { subscription }

    it 'terminates a subscription' do
      delete_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}")

      expect(response).to have_http_status(:success)
      expect(json[:subscription][:lago_id]).to eq(subscription.id)
      expect(json[:subscription][:status]).to eq('terminated')
      expect(json[:subscription][:terminated_at]).to be_present
    end

    context 'with not existing subscription' do
      it 'returns a not found error' do
        delete_with_token(organization, '/api/v1/subscriptions/123456')

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'update' do
    let(:subscription) { create(:subscription, :pending, customer:, plan:) }
    let(:update_params) do
      {
        name: 'subscription name new',
        subscription_at: '2022-09-05T12:23:12Z',
        plan_overrides: {
          name: 'plan new name',
          minimum_commitment: {
            invoice_display_name: commitment_invoice_display_name,
            amount_cents: 1234
          }
        }
      }
    end

    before { subscription }

    it 'updates a subscription', :aggregate_failures do
      put_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}", {subscription: update_params})

      expect(response).to have_http_status(:success)
      expect(json[:subscription][:lago_id]).to eq(subscription.id)
      expect(json[:subscription][:name]).to eq('subscription name new')
      expect(json[:subscription][:subscription_at].to_s).to eq('2022-09-05T12:23:12Z')

      expect(json[:subscription][:plan]).to include(
        name: 'plan new name'
      )

      expect(json[:subscription][:plan][:minimum_commitment]).to include(
        invoice_display_name: commitment_invoice_display_name,
        amount_cents: commitment_amount_cents
      )
    end

    context 'with not existing subscription' do
      it 'returns an not found error' do
        put_with_token(organization, '/api/v1/subscriptions/invalid', {subscription: update_params})

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with multuple subscriptions' do
      let(:active_plan) { create(:plan, organization:, amount_cents: 5000, description: 'desc') }
      let(:active_subscription) do
        create(:subscription, external_id: subscription.external_id, customer:, plan:)
      end

      before { active_subscription }

      it 'updates the active subscription', :aggregate_failures do
        put_with_token(
          organization,
          "/api/v1/subscriptions/#{subscription.external_id}",
          {subscription: update_params}
        )

        expect(response).to have_http_status(:success)
        expect(json[:subscription][:lago_id]).to eq(active_subscription.id)
        expect(json[:subscription][:name]).to eq('subscription name new')

        expect(json[:subscription][:plan]).to include(
          name: 'plan new name'
        )
      end

      context 'with pending params' do
        it 'updates the pending subscription' do
          put_with_token(
            organization,
            "/api/v1/subscriptions/#{subscription.external_id}",
            {subscription: update_params, status: 'pending'}
          )

          expect(response).to have_http_status(:success)
          expect(json[:subscription][:lago_id]).to eq(subscription.id)
          expect(json[:subscription][:name]).to eq('subscription name new')
          expect(json[:subscription][:subscription_at].to_s).to eq('2022-09-05T12:23:12Z')

          expect(json[:subscription][:plan]).to include(
            name: 'plan new name'
          )
        end
      end
    end
  end

  describe 'show' do
    let(:subscription) { create(:subscription, customer:, plan:) }

    it 'returns a subscription' do
      get_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}")

      expect(response).to have_http_status(:success)
      expect(json[:subscription]).to include(
        lago_id: subscription.id,
        external_id: subscription.external_id
      )
    end

    context 'when subscription does not exist' do
      it 'returns not found' do
        get_with_token(organization, '/api/v1/subscriptions/555')
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when status is given' do
      it 'returns the subscription with the given status' do
        pending = create(:subscription, customer:, plan:, status: :pending, external_id: subscription.external_id)
        get_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}?status=pending")

        expect(response).to have_http_status(:success)
        expect(json[:subscription]).to include(
          lago_id: pending.id,
          external_id: pending.external_id
        )
      end
    end
  end

  describe 'index' do
    let(:subscription1) { create(:subscription, customer:, plan:) }

    before { subscription1 }

    it 'returns subscriptions' do
      get_with_token(organization, "/api/v1/subscriptions?external_customer_id=#{customer.external_id}")

      expect(response).to have_http_status(:success)
      expect(json[:subscriptions].count).to eq(1)
      expect(json[:subscriptions].first[:lago_id]).to eq(subscription1.id)
    end

    context 'with next and previous subscriptions' do
      let(:previous_subscription) do
        create(
          :subscription,
          customer:,
          plan: create(:plan, organization:),
          status: :terminated
        )
      end

      let(:next_subscription) do
        create(
          :subscription,
          customer:,
          plan: create(:plan, organization:),
          status: :pending
        )
      end

      before do
        subscription1.update!(previous_subscription:, next_subscriptions: [next_subscription])
      end

      it 'returns next and previous plan code' do
        get_with_token(organization, "/api/v1/subscriptions?external_customer_id=#{customer.external_id}")

        subscription = json[:subscriptions].first
        expect(subscription[:previous_plan_code]).to eq(previous_subscription.plan.code)
        expect(subscription[:next_plan_code]).to eq(next_subscription.plan.code)
      end

      it 'returns the downgrade plan date' do
        current_date = DateTime.parse('20 Jun 2022')

        travel_to(current_date) do
          get_with_token(organization, "/api/v1/subscriptions?external_customer_id=#{customer.external_id}")

          subscription = json[:subscriptions].first
          expect(subscription[:downgrade_plan_date]).to eq('2022-07-01')
        end
      end
    end

    context 'with pagination' do
      let(:plan2) { create(:plan, organization:, amount_cents: 30_000) }
      let(:subscription2) { create(:subscription, customer:, plan: plan2) }

      before { subscription2 }

      it 'returns subscriptions with correct meta data' do
        get_with_token(
          organization,
          "/api/v1/subscriptions?external_customer_id=#{customer.external_id}&page=1&per_page=1"
        )

        expect(response).to have_http_status(:success)

        expect(json[:subscriptions].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end

    context 'with plan code' do
      it 'returns subscriptions' do
        get_with_token(organization, "/api/v1/subscriptions?plan_code=#{plan.code}")

        expect(response).to have_http_status(:success)
        expect(json[:subscriptions].count).to eq(1)
        expect(json[:subscriptions].first[:lago_id]).to eq(subscription1.id)
      end
    end

    context 'with terminated status' do
      let(:subscription3) { create(:subscription, customer:, plan: create(:plan, organization:), status: :terminated) }

      before { subscription3 }

      it 'returns terminated subscriptions' do
        get_with_token(organization, "/api/v1/subscriptions?external_customer_id=#{customer.external_id}&status[]=terminated")

        expect(response).to have_http_status(:success)
        expect(json[:subscriptions].count).to eq(1)
        expect(json[:subscriptions].first[:lago_id]).to eq(subscription3.id)
      end
    end
  end
end
