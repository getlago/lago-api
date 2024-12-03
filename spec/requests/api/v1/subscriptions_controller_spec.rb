# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::SubscriptionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 500, description: 'desc') }
  let(:commitment_invoice_display_name) { 'Overriden minimum commitment name' }
  let(:commitment_amount_cents) { 1234 }

  around { |test| lago_premium!(&test) }

  describe 'POST /api/v1/subscriptions' do
    subject { post_with_token(organization, '/api/v1/subscriptions', {subscription: params}) }

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
          },
          usage_thresholds: [
            amount_cents: override_amount_cents,
            threshold_display_name: override_display_name
          ]
        }
      }
    end

    let(:override_amount_cents) { 777 }
    let(:override_display_name) { 'Overriden Threshold 12' }

    it 'returns a success', :aggregate_failures do
      create(:plan, code: plan.code, parent_id: plan.id, organization:, description: 'foo')

      freeze_time do
        subject

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

    context 'when progressive billing premium integration is present' do
      around { |test| lago_premium!(&test) }

      before do
        organization.update!(premium_integrations: ['progressive_billing'])
      end

      it 'creates subscription with an overriden plan with usage thresholds' do
        subject

        expect(response).to have_http_status(:ok)

        expect(json[:subscription][:plan][:usage_thresholds].first).to include(
          amount_cents: override_amount_cents,
          threshold_display_name: override_display_name
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
        subject

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
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details]).to eq({external_customer_id: %w[value_is_mandatory]})
      end
    end

    context 'with invalid plan code' do
      let(:plan_code) { "#{plan.code}-invalid" }

      it 'returns a not_found error' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with invalid subscription_at' do
      let(:subscription_at) { 'hello' }

      it 'returns an unprocessable_entity error' do
        subject
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
        subject

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

  describe 'DELETE /api/v1subscriptions/:external_id' do
    subject { delete_with_token(organization, "/api/v1/subscriptions/#{external_id}") }

    let(:subscription) { create(:subscription, customer:, plan:) }
    let(:external_id) { subscription.external_id }

    it 'terminates a subscription' do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscription][:lago_id]).to eq(subscription.id)
      expect(json[:subscription][:status]).to eq('terminated')
      expect(json[:subscription][:terminated_at]).to be_present
    end

    context 'with not existing subscription' do
      let(:external_id) { SecureRandom.uuid }

      it 'returns a not found error' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PUT /api/v1/subscriptions/:external_id' do
    subject do
      put_with_token(
        organization,
        "/api/v1/subscriptions/#{external_id}",
        params
      )
    end

    let(:params) { {subscription: update_params} }
    let(:subscription) { create(:subscription, :pending, customer:, plan:) }
    let(:external_id) { subscription.external_id }

    let(:update_params) do
      {
        name: 'subscription name new',
        subscription_at: '2022-09-05T12:23:12Z',
        plan_overrides: {
          name: 'plan new name',
          minimum_commitment: {
            invoice_display_name: commitment_invoice_display_name,
            amount_cents: 1234
          },
          usage_thresholds: [
            id: usage_threshold.id,
            amount_cents: override_amount_cents,
            threshold_display_name: override_display_name
          ]
        }
      }
    end

    let(:override_amount_cents) { 999 }
    let(:override_display_name) { 'Overriden Threshold 1' }
    let(:usage_threshold) { create(:usage_threshold, plan:) }

    before do
      subscription
      usage_threshold
    end

    it 'updates a subscription', :aggregate_failures do
      subject

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

    context 'when progressive billing premium integration is present' do
      around { |test| lago_premium!(&test) }

      before do
        organization.update!(premium_integrations: ['progressive_billing'])
      end

      it 'updates subscription with an overriden plan with usage thresholds' do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:subscription][:plan][:usage_thresholds].first).to include(
          amount_cents: override_amount_cents,
          threshold_display_name: override_display_name
        )
      end
    end

    context 'with not existing subscription' do
      let(:external_id) { SecureRandom.uuid }

      it 'returns an not found error' do
        subject
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
        subject

        expect(response).to have_http_status(:success)
        expect(json[:subscription][:lago_id]).to eq(active_subscription.id)
        expect(json[:subscription][:name]).to eq('subscription name new')

        expect(json[:subscription][:plan]).to include(
          name: 'plan new name'
        )
      end

      context 'with pending params' do
        let(:params) { {subscription: update_params, status: 'pending'} }

        it 'updates the pending subscription' do
          subject

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

  describe 'GET /api/v1/subscriptions/:external_id' do
    subject do
      get_with_token(organization, "/api/v1/subscriptions/#{external_id}", params)
    end

    let(:params) { {} }
    let(:subscription) { create(:subscription, customer:, plan:) }
    let(:external_id) { subscription.external_id }

    it 'returns a subscription' do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscription]).to include(
        lago_id: subscription.id,
        external_id: subscription.external_id
      )
    end

    context 'when subscription does not exist' do
      let(:external_id) { SecureRandom.uuid }

      it 'returns not found' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when status is given' do
      let(:params) { {status: 'pending'} }

      let!(:matching_subscription) do
        create(:subscription, customer:, plan:, status: :pending, external_id: subscription.external_id)
      end

      it 'returns the subscription with the given status' do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:subscription]).to include(
          lago_id: matching_subscription.id,
          external_id: matching_subscription.external_id
        )
      end
    end
  end

  describe 'GET /api/v1/subscriptions' do
    subject { get_with_token(organization, "/api/v1/subscriptions", params) }

    let!(:subscription) { create(:subscription, customer:, plan:) }
    let(:params) { {external_customer_id: external_customer_id} }
    let(:external_customer_id) { customer.external_id }

    it 'returns subscriptions' do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscriptions].count).to eq(1)
      expect(json[:subscriptions].first[:lago_id]).to eq(subscription.id)
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
        subscription.update!(previous_subscription:, next_subscriptions: [next_subscription])
      end

      it 'returns next and previous plan code' do
        subject

        subscription = json[:subscriptions].first
        expect(subscription[:previous_plan_code]).to eq(previous_subscription.plan.code)
        expect(subscription[:next_plan_code]).to eq(next_subscription.plan.code)
      end

      it 'returns the downgrade plan date' do
        current_date = DateTime.parse('20 Jun 2022')

        travel_to(current_date) do
          subject

          subscription = json[:subscriptions].first
          expect(subscription[:downgrade_plan_date]).to eq('2022-07-01')
        end
      end
    end

    context 'with pagination' do
      let(:params) do
        {
          external_customer_id:,
          page: 1,
          per_page: 1
        }
      end

      before do
        another_plan = create(:plan, organization:, amount_cents: 30_000)
        create(:subscription, customer:, plan: another_plan)
      end

      it 'returns subscriptions with correct meta data' do
        subject

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
      let(:params) { {plan_code: plan.code} }

      it 'returns subscriptions' do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:subscriptions].count).to eq(1)
        expect(json[:subscriptions].first[:lago_id]).to eq(subscription.id)
      end
    end

    context 'with terminated status' do
      let!(:terminated_subscription) do
        create(:subscription, customer:, plan: create(:plan, organization:), status: :terminated)
      end

      let(:params) do
        {
          external_customer_id:,
          status: ['terminated']
        }
      end

      it 'returns terminated subscriptions' do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:subscriptions].count).to eq(1)
        expect(json[:subscriptions].first[:lago_id]).to eq(terminated_subscription.id)
      end
    end
  end
end
