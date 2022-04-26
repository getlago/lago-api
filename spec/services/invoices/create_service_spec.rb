# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::CreateService, type: :service do
  subject(:invoice_service) do
    described_class.new(subscription: subscription, timestamp: timestamp.to_i)
  end

  describe 'create' do
    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        anniversary_date: (Time.zone.now - 2.years).to_date,
        started_at: Time.zone.now - 2.years,
      )
    end

    let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }

    before do
      create(:charge, plan: subscription.plan, charge_model: 'standard')
    end

    context 'when billed monthly' do
      let(:timestamp) { Time.zone.now.beginning_of_month }

      let(:plan) do
        create(:plan, interval: 'monthly')
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.from_date).to eq(timestamp - 1.month)
          expect(result.invoice.subscription).to eq(subscription)
          expect(result.invoice.issuing_date.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)

          expect(result.invoice.amount_cents).to eq(100)
          expect(result.invoice.amount_currency).to eq('EUR')
          expect(result.invoice.vat_amount_cents).to eq(20)
          expect(result.invoice.vat_amount_currency).to eq('EUR')
          expect(result.invoice.total_amount_cents).to eq(120)
          expect(result.invoice.total_amount_currency).to eq('EUR')
        end
      end

      it 'enqueues a SendWebhookJob' do
        expect do
          invoice_service.create
        end.to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'when billed monthly on first month' do
      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:started_at) { timestamp - 3.days }

      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          anniversary_date: started_at.to_date,
          started_at: started_at,
        )
      end

      let(:plan) do
        create(:plan, interval: 'monthly')
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.from_date).to eq(subscription.anniversary_date)
          expect(result.invoice.subscription).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end
    end

    context 'when billed yearly' do
      let(:timestamp) { Time.zone.now.beginning_of_month }

      let(:plan) do
        create(:plan, interval: 'yearly')
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.from_date).to eq(timestamp - 1.year)
          expect(result.invoice.subscription).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end
    end

    context 'when billed yearly on first year' do
      let(:plan) do
        create(:plan, interval: 'yearly')
      end

      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:started_at) { Time.zone.today - 3.months }
      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          anniversary_date: started_at.to_date,
          started_at: started_at,
        )
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.from_date).to eq(subscription.anniversary_date)
          expect(result.invoice.subscription).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end
    end

    context 'when plan is pay in advance' do
      let(:plan) do
        create(:plan, interval: 'yearly', pay_in_advance: true)
      end

      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:started_at) { Time.zone.today - 3.months }
      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          anniversary_date: started_at.to_date,
          started_at: started_at,
        )
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result.invoice.issuing_date).to eq(timestamp.to_date)
        end
      end
    end

    context 'when subscription is terminated and plan is pay in arrear' do
      let(:plan) do
        create(:plan, interval: 'monthly', pay_in_advance: false)
      end

      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:started_at) { Time.zone.today - 3.months }
      let(:terminated_at) { timestamp - 2.days }
      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          anniversary_date: started_at.to_date,
          started_at: started_at,
          status: :terminated,
          terminated_at: terminated_at,
        )
      end

      it 'creates an invoice with subscription fee' do
        result = invoice_service.create

        aggregate_failures do
          expect(result.invoice.to_date.to_s).to eq((terminated_at.to_date - 1.day).to_s)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
        end
      end
    end

    context 'when subscription is terminated and upgraded' do
      let(:plan) do
        create(:plan, interval: 'monthly', pay_in_advance: false)
      end

      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:started_at) { Time.zone.today - 3.months }
      let(:terminated_at) { timestamp - 2.days }
      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          anniversary_date: started_at.to_date,
          started_at: started_at,
          status: :terminated,
          terminated_at: terminated_at,
        )
      end
      let(:next_plan) { create(:plan, amount_cents: plan.amount_cents + 20) }
      let(:next_subscription) do
        create(:subscription, plan: next_plan, previous_subscription: subscription)
      end

      before { next_subscription }

      it 'creates an invoice without charge fee' do
        result = invoice_service.create

        aggregate_failures do
          expect(result.invoice.to_date.to_s).to eq((terminated_at.to_date - 1.day).to_s)
          expect(result.invoice.fees.charge_kind.count).to eq(0)
        end
      end
    end
  end
end
