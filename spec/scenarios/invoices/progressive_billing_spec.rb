# frozen_string_literal: true

require 'rails_helper'

describe 'Progressive billing invoices', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: [], premium_integrations: ['progressive_billing']) }
  let(:plan) { create(:plan, organization: organization, interval: 'monthly', amount_cents: 12_900, pay_in_advance: false) }
  let(:new_plan) { create(:plan, organization: organization, interval: 'monthly', amount_cents: 25_000, pay_in_advance: false) }
  let(:customer) { create(:customer, organization: organization) }
  let(:billable_metric) { create(:billable_metric, organization: organization, field_name: 'total', aggregation_type: "sum_agg") }
  let(:charge) { create(:charge, plan: plan, billable_metric: billable_metric, charge_model: 'standard', properties: {'amount' => '0.0002'}) }
  let(:usage_threshold) { create(:usage_threshold, plan: plan, amount_cents: 1000) }
  let(:usage_threshold2) { create(:usage_threshold, plan: plan, amount_cents: 2000) }

  before do
    usage_threshold
    charge
  end

  around { |test| lago_premium!(&test) }

  def ingest_event(subscription, amount)
    create_event({
      transaction_id: SecureRandom.uuid,
      code: billable_metric.code,
      external_subscription_id: subscription.external_id,
      properties: { 'total' => amount }
    })
    perform_usage_update
  end

  it 'generates an invoice in the middle of the month and a final invoice at the end of the month' do
    time_0 = Time.current.beginning_of_month
    travel_to time_0 do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code
        }
      )

    end
    subscription = customer.subscriptions.first
    # creates invoice when threshold is reached first time
    travel_to time_0 + 5.days do
      ingest_event(subscription, 1000000)
      expect(Invoice.count).to eq(1)
      expect(Invoice.last.total_amount_cents).to eq(20000)
    end

    # creates invoice when threshold is reached second time
    travel_to time_0 + 15.days do
      ingest_event(subscription, 1000000)
      expect(Invoice.count).to eq(1)
      expect(Invoice.last.total_amount_cents).to eq(20000)
    end


    travel_to time_0 + 1.month do
      perform_billing
      expect(Invoice.count).to eq(2)
      expect(Invoice.last.total_amount_cents).to eq(32900)
    end
  end

  it 'generates an invoice in the middle of the month and terminates the subscription before the end of the month' do
    travel_to Time.current.middle_of_month
    ingest_event(100)
    expect(Invoice.count).to eq(1)

    travel_to Time.current.end_of_month - 1.day
    subscription.terminate!
    Invoice.finalize_all!
    expect(Invoice.count).to eq(2)
  end

  it 'generates an invoice in the middle of the month and upgrades the subscription before the end of the month' do
    travel_to Time.current.middle_of_month
    ingest_event(100)
    expect(Invoice.count).to eq(1)

    travel_to Time.current.end_of_month - 1.day
    subscription.update!(plan: new_plan)
    Invoice.finalize_all!
    expect(Invoice.count).to eq(2)
  end

  it 'generates an invoice during the grace period and finalizes it at the end of the next month' do
    organization.update!(grace_period: 1.month)
    travel_to Time.current.middle_of_month
    ingest_event(100)
    expect(Invoice.count).to eq(1)

    travel_to Time.current.end_of_month + 1.month
    ingest_event(100)
    Invoice.finalize_all!
    expect(Invoice.count).to eq(2)
  end

  it 'generates an invoice in the middle of the month and downgrades the subscription before the end of the month' do
    travel_to Time.current.middle_of_month
    ingest_event(100)
    expect(Invoice.count).to eq(1)

    travel_to Time.current.end_of_month - 1.day
    subscription.update!(plan: new_plan)
    Invoice.finalize_all!
    expect(Invoice.count).to eq(2)
  end

  it 'generates invoices for multiple usage thresholds within the same billing period' do
    travel_to Time.current.middle_of_month
    ingest_event(100)
    expect(Invoice.count).to eq(1)

    travel_to Time.current.middle_of_month + 5.days
    ingest_event(100)
    expect(Invoice.count).to eq(2)

    travel_to Time.current.end_of_month
    Invoice.finalize_all!
    expect(Invoice.count).to eq(3)
  end

  it 'generates only the final invoice at the end of the month' do
    travel_to Time.current.end_of_month
    Invoice.finalize_all!
    expect(Invoice.count).to eq(1)
  end
end
