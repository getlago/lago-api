# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::PlanSerializer do
  subject(:serializer) { described_class.new(plan, root_name: 'plan', includes: %i[charges taxes]) }

  let(:plan) { create(:plan) }
  let(:charge) { create(:standard_charge, plan:) }

  before { charge }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['plan']['lago_id']).to eq(plan.id)
      expect(result['plan']['name']).to eq(plan.name)
      expect(result['plan']['invoice_display_name']).to eq(plan.invoice_display_name)
      expect(result['plan']['created_at']).to eq(plan.created_at.iso8601)
      expect(result['plan']['code']).to eq(plan.code)
      expect(result['plan']['interval']).to eq(plan.interval)
      expect(result['plan']['description']).to eq(plan.description)
      expect(result['plan']['amount_cents']).to eq(plan.amount_cents)
      expect(result['plan']['amount_currency']).to eq(plan.amount_currency)
      expect(result['plan']['trial_period']).to eq(plan.trial_period)
      expect(result['plan']['pay_in_advance']).to eq(plan.pay_in_advance)
      expect(result['plan']['bill_charges_monthly']).to eq(plan.bill_charges_monthly)
      expect(result['plan']['active_subscriptions_count']).to eq(0)
      expect(result['plan']['draft_invoices_count']).to eq(0)
      expect(result['plan']['charges'].first['lago_id']).to eq(charge.id)
      expect(result['plan']['charges'].first['group_properties']).to eq([])

      expect(result['plan']['taxes']).to eq([])
    end
  end
end
