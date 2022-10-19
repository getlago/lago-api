# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::PlansController, type: :request do
  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization: organization) }

  describe 'create' do
    let(:create_params) do
      {
        name: 'P1',
        code: 'plan_code',
        interval: 'weekly',
        description: 'description',
        amount_cents: 100,
        amount_currency: 'EUR',
        trial_period: 1,
        pay_in_advance: false,
        charges: [
          {
            billable_metric_id: billable_metric.id,
            charge_model: 'standard',
            properties: {
              amount: '0.22',
            },
          },
        ],
      }
    end

    it 'creates a plan' do
      post_with_token(organization, '/api/v1/plans', { plan: create_params })

      expect(response).to have_http_status(:success)

      expect(json[:plan][:lago_id]).to be_present
      expect(json[:plan][:code]).to eq(create_params[:code])
      expect(json[:plan][:name]).to eq(create_params[:name])
      expect(json[:plan][:created_at]).to be_present
      expect(json[:plan][:charges].first[:lago_id]).to be_present
    end

    context 'with graduated charges' do
      let(:create_params) do
        {
          name: 'P1',
          code: 'plan_code',
          interval: 'weekly',
          description: 'description',
          amount_cents: 100,
          amount_currency: 'EUR',
          trial_period: 1,
          pay_in_advance: false,
          charges: [
            {
              billable_metric_id: billable_metric.id,
              charge_model: 'graduated',
              properties: {
                graduated_ranges: [
                  {
                    to_value: 1,
                    from_value: 0,
                    flat_amount: '0',
                    per_unit_amount: '0',
                  },
                  {
                    to_value: nil,
                    from_value: 2,
                    flat_amount: '0',
                    per_unit_amount: '3200',
                  },
                ],
              },
            },
          ],
        }
      end

      it 'creates a plan' do
        post_with_token(organization, '/api/v1/plans', { plan: create_params })

        expect(response).to have_http_status(:success)

        expect(json[:plan][:lago_id]).to be_present
        expect(json[:plan][:code]).to eq(create_params[:code])
        expect(json[:plan][:name]).to eq(create_params[:name])
        expect(json[:plan][:created_at]).to be_present
        expect(json[:plan][:charges].first[:lago_id]).to be_present
      end
    end

    context 'with group properties on charges' do
      let(:group) { create(:group, billable_metric: billable_metric) }
      let(:create_params) do
        {
          name: 'P1',
          code: 'plan_code',
          interval: 'weekly',
          description: 'description',
          amount_cents: 100,
          amount_currency: 'EUR',
          trial_period: 1,
          pay_in_advance: false,
          charges: [
            {
              billable_metric_id: billable_metric.id,
              charge_model: 'standard',
              group_properties: [
                {
                  group_id: group.id,
                  values: { amount: '0.22' },
                },
              ],
            },
          ],
        }
      end

      it 'creates a plan' do
        post_with_token(organization, '/api/v1/plans', { plan: create_params })

        expect(response).to have_http_status(:success)

        expect(json[:plan][:lago_id]).to be_present
        expect(json[:plan][:code]).to eq(create_params[:code])
        expect(json[:plan][:charges].first[:group_properties]).to eq(
          [
            {
              group_id: group.id,
              values: { amount: '0.22' },
            },
          ],
        )
      end
    end

    context 'without charges' do
      let(:create_params) do
        {
          name: 'P1',
          code: 'plan_code',
          interval: 'weekly',
          description: 'description',
          amount_cents: 100,
          amount_currency: 'EUR',
          trial_period: 1,
          pay_in_advance: false,
        }
      end

      it 'creates a plan' do
        post_with_token(organization, '/api/v1/plans', { plan: create_params })

        expect(response).to have_http_status(:success)

        expect(json[:plan][:lago_id]).to be_present
        expect(json[:plan][:code]).to eq(create_params[:code])
        expect(json[:plan][:name]).to eq(create_params[:name])
        expect(json[:plan][:created_at]).to be_present
        expect(json[:plan][:charges].count).to eq(0)
      end
    end
  end

  describe 'update' do
    let(:plan) { create(:plan, organization: organization) }
    let(:code) { 'plan_code' }
    let(:update_params) do
      {
        name: 'P1',
        code: code,
        interval: 'weekly',
        description: 'description',
        amount_cents: 100,
        amount_currency: 'EUR',
        trial_period: 1,
        pay_in_advance: false,
        charges: [
          {
            billable_metric_id: billable_metric.id,
            charge_model: 'standard',
            properties: {
              amount: '0.22',
            },
          },
        ],
      }
    end

    it 'updates a plan' do
      put_with_token(
        organization,
        "/api/v1/plans/#{plan.code}",
        { plan: update_params },
      )

      expect(response).to have_http_status(:success)
      expect(json[:plan][:lago_id]).to eq(plan.id)
      expect(json[:plan][:code]).to eq(update_params[:code])
    end

    context 'when plan does not exist' do
      it 'returns not_found error' do
        put_with_token(organization, '/api/v1/plans/invalid', { plan: update_params })

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when plan code already exists in organization scope (validation error)' do
      let(:plan2) { create(:plan, organization: organization) }
      let(:code) { plan2.code }

      before { plan2 }

      it 'returns unprocessable_entity error' do
        put_with_token(
          organization,
          "/api/v1/plans/#{plan.code}",
          { plan: update_params },
        )

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with group properties on charges' do
      let(:group) { create(:group, billable_metric: billable_metric) }
      let(:update_params) do
        {
          name: 'P1',
          code: 'plan_code',
          interval: 'weekly',
          description: 'description',
          amount_cents: 100,
          amount_currency: 'EUR',
          trial_period: 1,
          pay_in_advance: false,
          charges: [
            {
              billable_metric_id: billable_metric.id,
              charge_model: 'standard',
              group_properties: [
                {
                  group_id: group.id,
                  values: { amount: '0.22' },
                },
              ],
            },
          ],
        }
      end

      it 'creates a plan' do
        put_with_token(organization, "/api/v1/plans/#{plan.code}", { plan: update_params })

        expect(response).to have_http_status(:success)

        expect(json[:plan][:lago_id]).to be_present
        expect(json[:plan][:code]).to eq(update_params[:code])
        expect(json[:plan][:charges].first[:group_properties]).to eq(
          [
            {
              group_id: group.id,
              values: { amount: '0.22' },
            },
          ],
        )
      end
    end
  end

  describe 'show' do
    let(:plan) { create(:plan, organization: organization) }

    it 'returns a plan' do
      get_with_token(
        organization,
        "/api/v1/plans/#{plan.code}",
      )

      expect(response).to have_http_status(:success)
      expect(json[:plan][:lago_id]).to eq(plan.id)
      expect(json[:plan][:code]).to eq(plan.code)
    end

    context 'when plan does not exist' do
      it 'returns not found' do
        get_with_token(
          organization,
          '/api/v1/plans/555',
        )

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'destroy' do
    let(:plan) { create(:plan, organization: organization) }

    before { plan }

    it 'deletes a plan' do
      expect { delete_with_token(organization, "/api/v1/plans/#{plan.code}") }
        .to change(Plan, :count).by(-1)
    end

    it 'returns deleted plan' do
      delete_with_token(organization, "/api/v1/plans/#{plan.code}")

      expect(response).to have_http_status(:success)
      expect(json[:plan][:lago_id]).to eq(plan.id)
      expect(json[:plan][:code]).to eq(plan.code)
    end

    context 'when plan does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, '/api/v1/plans/invalid')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when plan is attached to active subscription' do
      let(:subscription) { create(:subscription, plan: plan) }
      let(:plan) { create(:plan, organization: organization) }

      before { subscription }

      it 'returns forbidden error' do
        delete_with_token(organization, "/api/v1/plans/#{plan.code}")

        aggregate_failures do
          expect(response).to have_http_status(:method_not_allowed)

          expect(json[:status]).to eq(405)
          expect(json[:error]).to eq('Method Not Allowed')
          expect(json[:code]).to eq('attached_to_an_active_subscription')
        end
      end
    end
  end

  describe 'index' do
    let(:plan) { create(:plan, organization: organization) }

    before { plan }

    it 'returns plans' do
      get_with_token(organization, '/api/v1/plans')

      expect(response).to have_http_status(:success)

      expect(json[:plans].count).to eq(1)
      expect(json[:plans].first[:lago_id]).to eq(plan.id)
      expect(json[:plans].first[:code]).to eq(plan.code)
    end

    context 'with pagination' do
      let(:plan2) { create(:plan, organization: organization) }

      before { plan2 }

      it 'returns plans with correct meta data' do
        get_with_token(organization, '/api/v1/plans?page=1&per_page=1')

        expect(response).to have_http_status(:success)

        expect(json[:plans].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end
  end
end
