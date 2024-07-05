# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::PlanSerializer do
  subject(:serializer) { described_class.new(plan, root_name: 'plan', includes: %i[charges taxes minimum_commitment]) }

  let(:plan) { create(:plan) }
  let(:customer) { create(:customer, organization: plan.organization) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:charge) { create(:standard_charge, plan:) }

  before { subscription && charge }

  context 'when plan has one minimium commitment' do
    let(:commitment) { create(:commitment, plan:) }

    before { commitment }

    it 'serializes the object', :aggregate_failures do
      overridden_plan = create(:plan, parent_id: plan.id)
      customer2 = create(:customer, organization: plan.organization)
      create(:subscription, customer: customer2, plan: overridden_plan)

      result = JSON.parse(serializer.to_json)

      expect(result['plan']).to include(
        'lago_id' => plan.id,
        'name' => plan.name,
        'invoice_display_name' => plan.invoice_display_name,
        'created_at' => plan.created_at.iso8601,
        'code' => plan.code,
        'interval' => plan.interval,
        'description' => plan.description,
        'amount_cents' => plan.amount_cents,
        'amount_currency' => plan.amount_currency,
        'trial_period' => plan.trial_period,
        'pay_in_advance' => plan.pay_in_advance,
        'bill_charges_monthly' => plan.bill_charges_monthly,
        'customers_count' => 2,
        'active_subscriptions_count' => 2,
        'draft_invoices_count' => 0,
        'parent_id' => nil,
        'taxes' => []
      )

      expect(result['plan']['charges'].first).to include(
        'lago_id' => charge.id
      )

      expect(result['plan']['minimum_commitment']).to include(
        'lago_id' => commitment.id,
        'plan_code' => commitment.plan.code,
        'invoice_display_name' => commitment.invoice_display_name,
        'amount_cents' => commitment.amount_cents,
        'interval' => commitment.plan.interval,
        'created_at' => commitment.created_at.iso8601,
        'updated_at' => commitment.updated_at.iso8601,
        'taxes' => []
      )
      expect(result['plan']['minimum_commitment']).not_to include(
        'commitment_type' => 'minimum_commitment'
      )
    end
  end

  context 'when plan has no minimium commitment' do
    it 'serializes the object', :aggregate_failures do
      overridden_plan = create(:plan, parent_id: plan.id)
      customer2 = create(:customer, organization: plan.organization)
      create(:subscription, customer: customer2, plan: overridden_plan)

      result = JSON.parse(serializer.to_json)

      expect(result['plan']).to include(
        'lago_id' => plan.id,
        'name' => plan.name,
        'invoice_display_name' => plan.invoice_display_name,
        'created_at' => plan.created_at.iso8601,
        'code' => plan.code,
        'interval' => plan.interval,
        'description' => plan.description,
        'amount_cents' => plan.amount_cents,
        'amount_currency' => plan.amount_currency,
        'trial_period' => plan.trial_period,
        'pay_in_advance' => plan.pay_in_advance,
        'bill_charges_monthly' => plan.bill_charges_monthly,
        'customers_count' => 2,
        'active_subscriptions_count' => 2,
        'draft_invoices_count' => 0,
        'parent_id' => nil,
        'taxes' => []
      )

      expect(result['plan']['charges'].first).to include(
        'lago_id' => charge.id
      )

      expect(result['plan']['minimum_commitment']).to be_nil
    end
  end
end
