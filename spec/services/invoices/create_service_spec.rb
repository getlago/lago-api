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
        subscription_date: (Time.zone.now - 2.years).to_date,
        started_at: Time.zone.now - 2.years,
      )
    end

    let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
    let(:timestamp) { Time.zone.now.beginning_of_month }

    let(:plan) do
      create(:plan, interval: 'monthly')
    end

    before do
      create(:standard_charge, plan: subscription.plan, charge_model: 'standard')
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'calls SegmentTrackJob' do
      invoice = invoice_service.create.invoice

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type
        }
      )
    end

    context 'when billed monthly' do
      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.from_date).to eq(timestamp - 1.month)
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.issuing_date.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.invoice_type).to eq('subscription')
          expect(result.invoice.status).to eq('pending')
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

      context 'when organization does not have a webhook url' do
        before { subscription.organization.update!(webhook_url: nil) }

        it 'does not enqueues a SendWebhookJob' do
          expect do
            invoice_service.create
          end.not_to have_enqueued_job(SendWebhookJob)
        end
      end

      context 'when customer payment_provider is stripe' do
        before { subscription.customer.update!(payment_provider: 'stripe') }

        it 'enqueu a job to create a payment' do
          expect do
            invoice_service.create
          end.to have_enqueued_job(Invoices::Payments::StripeCreateJob)
        end
      end
    end

    context 'when billed monthly on first month' do
      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:started_at) { timestamp - 3.days }

      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_date: started_at.to_date,
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
          expect(result.invoice.from_date).to eq(subscription.subscription_date)
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end
    end

    context 'when billed weekly' do
      let(:timestamp) { Time.zone.now.beginning_of_week }

      let(:plan) do
        create(:plan, interval: 'weekly')
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.from_date).to eq(timestamp - 1.week)
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end
    end

    context 'when billed weekly on first week' do
      let(:timestamp) { Time.zone.now.beginning_of_week }
      let(:started_at) { timestamp - 3.days }

      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_date: started_at.to_date,
          started_at: started_at,
        )
      end

      let(:plan) do
        create(:plan, interval: 'weekly')
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.from_date).to eq(subscription.subscription_date)
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end
    end

    context 'when billed yearly' do
      let(:timestamp) { Time.zone.now.beginning_of_year }

      let(:plan) do
        create(:plan, interval: 'yearly')
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.from_date).to eq(timestamp - 1.year)
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end

      context 'when plan has bill charges monthly option' do
        before { plan.update(bill_charges_monthly: true) }

        context 'when subscription has already been billed' do
          before do
            first_invoice_timestamp = (subscription.started_at.end_of_year + 1.day).to_i
            described_class.new(subscription: subscription, timestamp: first_invoice_timestamp).create
          end

          let(:timestamp) { (subscription.started_at.end_of_year + 1.month + 1.day).to_i }

          it 'creates an invoice for charges' do
            result = invoice_service.create

            aggregate_failures do
              expect(result).to be_success

              expect(result.invoice.fees.subscription_kind.count).to eq(0)
              expect(result.invoice.fees.charge_kind.count).to eq(1)
              expect(result.invoice.charges_from_date).to eq(Time.zone.at(timestamp).to_date - 1.month)
            end
          end
        end
      end
    end

    context 'when billed yearly on first year' do
      let(:plan) do
        create(:plan, interval: 'yearly')
      end

      let(:timestamp) { Time.zone.now.end_of_year + 1.day }
      let(:started_at) { Time.zone.today - 3.months }
      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_date: started_at.to_date,
          started_at: started_at,
        )
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq((timestamp - 1.day).to_date)
          expect(result.invoice.from_date).to eq(subscription.subscription_date)
          expect(result.invoice.subscriptions.first).to eq(subscription)
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
          subscription_date: started_at.to_date,
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

      let(:timestamp) { Time.zone.now.beginning_of_month - 1.day }
      let(:started_at) { Time.zone.today - 3.months }
      let(:terminated_at) { timestamp - 2.days }
      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_date: started_at.to_date,
          started_at: started_at,
          status: :terminated,
          terminated_at: terminated_at,
        )
      end

      it 'creates an invoice with subscription fee' do
        result = invoice_service.create

        aggregate_failures do
          expect(result.invoice.to_date.to_s).to eq((terminated_at.to_date - 1.day).to_s)
          expect(result.invoice.from_date.to_s).to eq((terminated_at.to_date.beginning_of_month).to_s)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
        end
      end
    end

    context 'when subscription is terminated and upgraded' do
      let(:plan) do
        create(:plan, interval: 'monthly', pay_in_advance: false)
      end

      let(:timestamp) { Time.zone.now.beginning_of_month - 1.day }
      let(:started_at) { Time.zone.today - 3.months }
      let(:terminated_at) { timestamp - 2.days }
      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_date: started_at.to_date,
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
          expect(result.invoice.from_date.to_s).to eq((terminated_at.to_date.beginning_of_month).to_s)
          expect(result.invoice.fees.charge_kind.count).to eq(0)
        end
      end
    end

    context 'when subscription is pay in advance and is an upgrade' do
      let(:plan) do
        create(:plan, interval: :monthly, pay_in_advance: true, amount_cents: 1000)
      end

      let(:timestamp) { Time.zone.now.beginning_of_month - 1.day }
      let(:started_at) { Time.zone.today - 3.months }
      let(:terminated_at) { timestamp - 2.days }
      let(:previous_plan) { create(:plan, amount_cents: 10000, interval: :yearly, pay_in_advance: true) }

      let(:previous_subscription) do
        create(
          :subscription,
          plan: previous_plan,
          subscription_date: started_at.to_date,
          started_at: started_at,
          status: :terminated,
          terminated_at: terminated_at,
        )
      end

      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          previous_subscription: previous_subscription,
          subscription_date: started_at.to_date,
          started_at: terminated_at + 1.day,
        )
      end

      before { subscription }

      it 'creates an invoice without charge fee and with amount equal to zero' do
        result = invoice_service.create

        aggregate_failures do
          expect(result.invoice.to_date.to_s).to eq(subscription.started_at.to_date.to_s)
          expect(result.invoice.from_date.to_s).to eq(subscription.started_at.to_date.to_s)
          expect(result.invoice.total_amount_cents).to eq(0)
          expect(result.invoice.status).to eq('succeeded')
          expect(result.invoice.fees.charge_kind.count).to eq(0)
        end
      end
    end

    context 'with applied coupon' do
      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:applied_coupon) do
        create(
          :applied_coupon,
          customer: subscription.customer,
          amount_cents: 10,
          amount_currency: plan.amount_currency,
        )
      end

      let(:plan) do
        create(:plan, interval: 'monthly')
      end

      before { applied_coupon }

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.from_date).to eq(timestamp - 1.month)
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.issuing_date.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)

          expect(result.invoice.amount_cents).to eq(90)
          expect(result.invoice.amount_currency).to eq('EUR')
          expect(result.invoice.vat_amount_cents).to eq(18)
          expect(result.invoice.vat_amount_currency).to eq('EUR')
          expect(result.invoice.total_amount_cents).to eq(108)
          expect(result.invoice.total_amount_currency).to eq('EUR')

          expect(result.invoice.credits.count).to eq(1)
        end
      end

      context 'when coupon has a difference currency' do
        let(:applied_coupon) do
          create(
            :applied_coupon,
            customer: subscription.customer,
            amount_cents: 10,
            amount_currency: 'NOK',
          )
        end

        it 'ignore the coupon' do
          result = invoice_service.create

          expect(result).to be_success
          expect(result.invoice.credits.count).to be_zero
        end
      end
    end
  end
end
