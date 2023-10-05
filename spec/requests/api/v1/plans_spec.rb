# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::PlansController, type: :request do
  let(:tax) { create(:tax, organization:) }
  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:plan) { create(:plan, code: 'plan_code') }

  describe 'create' do
    let(:create_params) do
      {
        name: 'P1',
        invoice_display_name: 'P1 invoice name',
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
            tax_codes:,
          },
        ],
      }
    end
    let(:tax_codes) { [tax.code] }

    it 'creates a plan' do
      post_with_token(organization, '/api/v1/plans', { plan: create_params })

      expect(response).to have_http_status(:success)

      expect(json[:plan][:lago_id]).to be_present
      expect(json[:plan][:code]).to eq(create_params[:code])
      expect(json[:plan][:name]).to eq(create_params[:name])
      expect(json[:plan][:invoice_display_name]).to eq(create_params[:invoice_display_name])
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
      let(:group) { create(:group, billable_metric:) }
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
                  invoice_display_name: 'Europe',
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
              invoice_display_name: 'Europe',
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

    context 'with unknown tax code on charge' do
      let(:tax_codes) { ['unknown'] }

      it 'returns a 404 response' do
        post_with_token(organization, '/api/v1/plans', { plan: create_params })

        aggregate_failures do
          expect(response).to have_http_status(:not_found)
          expect(json[:error]).to eq('Not Found')
          expect(json[:code]).to eq('tax_not_found')
        end
      end
    end
  end

  describe 'update' do
    let(:plan) { create(:plan, organization:) }
    let(:code) { 'plan_code' }
    let(:tax_codes) { [tax.code] }
    let(:update_params) do
      {
        name: 'P1',
        code:,
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
            tax_codes:,
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
      let(:plan2) { create(:plan, organization:) }
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
      let(:group) { create(:group, billable_metric:) }
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
                  invoice_display_name: 'Europe',
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
              invoice_display_name: 'Europe',
              values: { amount: '0.22' },
            },
          ],
        )
      end
    end
  end

  describe 'show' do
    let(:plan) { create(:plan, organization:) }

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
    let(:plan) { create(:plan, organization:) }

    it 'marks plan as pending_deletion' do
      expect { delete_with_token(organization, "/api/v1/plans/#{plan.code}") }
        .to change { plan.reload.pending_deletion }.from(false).to(true)
    end

    it 'marks children plan as pending_deletion' do
      children_plan = create(:plan, parent_id: plan.id)

      expect { delete_with_token(organization, "/api/v1/plans/#{plan.code}") }
        .to change { children_plan.reload.pending_deletion }.from(false).to(true)
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
  end

  describe 'index' do
    let(:plan) { create(:plan, organization:) }

    before { plan }

    it 'returns plans' do
      get_with_token(organization, '/api/v1/plans')

      expect(response).to have_http_status(:success)

      expect(json[:plans].count).to eq(1)
      expect(json[:plans].first[:lago_id]).to eq(plan.id)
      expect(json[:plans].first[:code]).to eq(plan.code)
    end

    context 'with pagination' do
      let(:plan2) { create(:plan, organization:) }

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
