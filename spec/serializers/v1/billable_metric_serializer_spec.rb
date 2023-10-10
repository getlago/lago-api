# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::BillableMetricSerializer do
  subject(:serializer) { described_class.new(billable_metric, root_name: 'billable_metric') }

  let(:billable_metric) { create(:weighted_sum_billable_metric) }
  let(:result) { JSON.parse(serializer.to_json) }

  it 'serializes the object' do
    aggregate_failures do
      expect(result['billable_metric']['lago_id']).to eq(billable_metric.id)
      expect(result['billable_metric']['name']).to eq(billable_metric.name)
      expect(result['billable_metric']['code']).to eq(billable_metric.code)
      expect(result['billable_metric']['description']).to eq(billable_metric.description)
      expect(result['billable_metric']['aggregation_type']).to eq(billable_metric.aggregation_type)
      expect(result['billable_metric']['field_name']).to eq(billable_metric.field_name)
      expect(result['billable_metric']['created_at']).to eq(billable_metric.created_at.iso8601)
      expect(result['billable_metric']['weighted_interval']).to eq(billable_metric.weighted_interval)
      expect(result['billable_metric']['group']).to eq({})
      expect(result['billable_metric']['active_subscriptions_count']).to eq(0)
      expect(result['billable_metric']['draft_invoices_count']).to eq(0)
      expect(result['billable_metric']['plans_count']).to eq(0)
    end
  end

  it 'returns the count number of active subscriptions' do
    terminated_subscription = create(:subscription, :terminated)
    create(:standard_charge, plan: terminated_subscription.plan, billable_metric:)

    subscription = create(:subscription)
    create(:standard_charge, plan: subscription.plan, billable_metric:)

    expect(result['billable_metric']['active_subscriptions_count']).to eq(1)
  end

  it 'returns the count number of draft invoices' do
    customer = create(:customer, organization: billable_metric.organization)
    subscription = create(:subscription)
    subscription2 = create(:subscription)
    charge = create(:standard_charge, plan: subscription.plan, billable_metric:)
    charge2 = create(:standard_charge, plan: subscription2.plan, billable_metric:)

    invoice = create(:invoice, customer:, organization: billable_metric.organization)
    create(:fee, invoice:, charge:)

    draft_invoice = create(:invoice, :draft, customer:, organization: billable_metric.organization)
    create(:fee, invoice: draft_invoice, charge: charge2)
    create(:fee, invoice: draft_invoice, charge: charge2)

    expect(result['billable_metric']['draft_invoices_count']).to eq(1)
  end

  it 'returns the number of plans' do
    plan = create(:plan, organization: billable_metric.organization)
    create(:standard_charge, billable_metric:, plan:)

    expect(result['billable_metric']['plans_count']).to eq(1)
  end
end
