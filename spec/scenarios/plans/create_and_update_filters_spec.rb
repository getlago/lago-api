# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Create and edit plans with charge filters', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:billable_metric) { create(:billable_metric, organization:) }

  let(:steps_bm_filter) do
    create(:billable_metric_filter, billable_metric:, key: 'steps', values: %w[0-25 26-50 51-100])
  end
  let(:image_size_bm_filter) do
    create(:billable_metric_filter, billable_metric:, key: 'image_size', values: %w[1024x1024 512x152])
  end
  let(:model_name_bm_filter) do
    create(:billable_metric_filter, billable_metric:, key: 'model_name', values: %w[llama-1 llama-2 llama-3])
  end

  before do
    steps_bm_filter
    image_size_bm_filter
    model_name_bm_filter
  end

  it 'allows the creation and update of plans with charge filters' do
    # Create a plan with a charge and filters
    create_plan(
      name: 'Filtered Plan',
      code: 'filtered_plan',
      interval: 'monthly',
      amount_cents: 10_000,
      amount_currency: 'EUR',
      pay_in_advance: false,
      charges: [
        {
          billable_metric_id: billable_metric.id,
          charge_model: 'standard',
          properties: { amount: '0' },
          filters: [
            {
              invoice_display_name: 'f1',
              properties: { amount: '10' },
              values: { image_size: ['512x152'], steps: ['0-25'], model_name: ['llama-2'] },
            },
            {
              invoice_display_name: 'f2',
              properties: { amount: '5' },
              values: { image_size: ['512x152'], steps: ['0-25'] },
            },
            {
              invoice_display_name: 'f3',
              properties: { amount: '5' },
              values: {
                image_size: [ChargeFilterValue::ALL_FILTER_VALUES],
                steps: [ChargeFilterValue::ALL_FILTER_VALUES],
              },
            },
            {
              invoice_display_name: 'f4',
              properties: { amount: '2.5' },
              values: {
                image_size: [ChargeFilterValue::ALL_FILTER_VALUES],
              },
            },
          ],
        },
      ],
    )

    plan = organization.plans.find_by(code: 'filtered_plan')
    expect(plan.charges.count).to eq(1)

    charge = plan.charges.first
    expect(charge.filters.count).to eq(4)

    # Update the typo on the charge filter values
    update_metric(
      billable_metric,
      filters: [
        { key: 'image_size', values: %w[1024x1024 512x512] },
        { key: 'steps', values: %w[0-25 26-50 51-100] },
        { key: 'model_name', values: %w[llama-1 llama-2 llama-3] },
      ],
    )

    charge.reload
    f1 = charge.filters.find_by(invoice_display_name: 'f1')
    expect(f1.to_h.keys).to eq(%w[steps model_name])

    f2 = charge.filters.find_by(invoice_display_name: 'f2')
    expect(f2.to_h.keys).to eq(%w[steps])

    f3 = charge.filters.find_by(invoice_display_name: 'f3')
    expect(f3.to_h.keys).to eq(%w[image_size steps])

    f4 = charge.filters.find_by(invoice_display_name: 'f4')
    expect(f4.to_h.keys).to eq(%w[image_size])

    # Update the plan to fix the filters
    update_plan(
      plan,
      name: 'Filtered Plan',
      code: 'filtered_plan',
      interval: 'monthly',
      amount_cents: 10_000,
      amount_currency: 'EUR',
      pay_in_advance: false,
      charges: [
        {
          billable_metric_id: billable_metric.id,
          id: charge.id,
          charge_model: 'standard',
          properties: { amount: '0' },
          filters: [
            {
              invoice_display_name: 'f2',
              properties: { amount: '5' },
              values: { image_size: ['512x512'], steps: ['0-25'] },
            },
            {
              invoice_display_name: 'f3',
              properties: { amount: '5' },
              values: {
                image_size: [ChargeFilterValue::ALL_FILTER_VALUES],
                steps: [ChargeFilterValue::ALL_FILTER_VALUES],
              },
            },
            {
              invoice_display_name: 'f4',
              properties: { amount: '2.5' },
              values: {
                image_size: [ChargeFilterValue::ALL_FILTER_VALUES],
              },
            },
            {
              invoice_display_name: 'f1',
              properties: { amount: '10' },
              values: { image_size: ['512x512'], steps: ['0-25'], model_name: ['llama-2'] },
            },
          ],
        },
      ],
    )

    plan.reload
    charge = plan.charges.first
    expect(charge.filters.count).to eq(4)
  end
end
