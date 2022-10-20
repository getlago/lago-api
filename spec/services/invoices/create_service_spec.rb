# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::CreateService, type: :service do
  subject(:invoice_service) do
    described_class.new(subscriptions: subscriptions, timestamp: timestamp.to_i)
  end

  describe 'create' do
    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        subscription_date: started_at.to_date,
        started_at: started_at,
        created_at: started_at,
      )
    end
    let(:subscriptions) { [subscription] }

    let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
    let(:timestamp) { Time.zone.now.beginning_of_month }
    let(:started_at) { Time.zone.now - 2.years }

    let(:plan) { create(:plan, interval: 'monthly', pay_in_advance: pay_in_advance) }
    let(:pay_in_advance) { false }

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
          invoice_type: invoice.invoice_type,
        },
      )
    end

    context 'when billed monthly' do
      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_date']).to eq (timestamp - 1.day).to_date.to_s
          expect(result.invoice.fees.first.properties['from_date']).to eq (timestamp - 1.month).to_date.to_s
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.issuing_date.to_date).to eq(timestamp)
          expect(result.invoice.invoice_type).to eq('subscription')
          expect(result.invoice.status).to eq('pending')
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)

          expect(result.invoice.amount_cents).to eq(100)
          expect(result.invoice.amount_currency).to eq('EUR')
          expect(result.invoice.vat_amount_cents).to eq(20)
          expect(result.invoice.vat_amount_currency).to eq('EUR')
          expect(result.invoice.vat_rate).to eq(20)
          expect(result.invoice.credit_amount_cents).to eq(0)
          expect(result.invoice.credit_amount_currency).to eq('EUR')
          expect(result.invoice.total_amount_cents).to eq(120)
          expect(result.invoice.total_amount_currency).to eq('EUR')

          expect(result.invoice).to be_legacy
        end
      end

      it 'enqueues a SendWebhookJob' do
        expect do
          invoice_service.create
        end.to have_enqueued_job(SendWebhookJob)
      end

      context 'when organization does not have a webhook url' do
        before { subscription.customer.organization.update!(webhook_url: nil) }

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

      context 'when plan is pay in advance and subscription fees are created earlier today' do
        let(:pay_in_advance) { true }
        let(:timestamp) { Time.current.to_i }

        before { create(:fee, subscription: subscription) }

        it 'creates an invoice for without subscription fees' do
          result = invoice_service.create

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.fees.subscription_kind.count).to eq(0)
          end
        end
      end

      context 'when plan is pay in advance and subscription started in the past' do
        let(:pay_in_advance) { true }
        let(:created_at) { timestamp }
        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            subscription_date: started_at.to_date,
            started_at: started_at,
            created_at: timestamp,
          )
        end

        it 'creates an invoice with charge fees' do
          result = invoice_service.create

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.fees.charge_kind.count).to eq(1)
          end
        end
      end

      context 'when plan is pay in advance and subscription started on creation day' do
        let(:pay_in_advance) { true }

        it 'creates an invoice with charge fees' do
          result = invoice_service.create

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.fees.charge_kind.count).to eq(0)
          end
        end
      end

      context 'when subscription is billed on anniversary date' do
        let(:timestamp) { DateTime.parse('07 Mar 2022') }
        let(:started_at) { DateTime.parse('06 Jun 2021').to_date }
        let(:subscription_date) { started_at }

        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            subscription_date: subscription_date,
            started_at: started_at,
            billing_time: :anniversary,
            created_at: started_at,
          )
        end

        it 'creates an invoice' do
          result = invoice_service.create

          aggregate_failures do
            expect(result).to be_success

            expect(result.invoice.fees.first.properties['to_date']).to eq('2022-03-05')
            expect(result.invoice.fees.first.properties['from_date']).to eq('2022-02-06')
            expect(result.invoice.subscriptions.first).to eq(subscription)
            expect(result.invoice.issuing_date.to_date).to eq(timestamp)
            expect(result.invoice.invoice_type).to eq('subscription')
            expect(result.invoice.status).to eq('pending')
            expect(result.invoice.fees.subscription_kind.count).to eq(1)
            expect(result.invoice.fees.charge_kind.count).to eq(1)

            expect(result.invoice.amount_cents).to eq(100)
            expect(result.invoice.amount_currency).to eq('EUR')
            expect(result.invoice.vat_amount_cents).to eq(20)
            expect(result.invoice.vat_amount_currency).to eq('EUR')
            expect(result.invoice.vat_rate).to eq(20)
            expect(result.invoice.credit_amount_cents).to eq(0)
            expect(result.invoice.credit_amount_currency).to eq('EUR')
            expect(result.invoice.total_amount_cents).to eq(120)
            expect(result.invoice.total_amount_currency).to eq('EUR')

            expect(result.invoice).to be_legacy
          end
        end

        context 'when plan is pay in advance' do
          let(:pay_in_advance) { true }

          it 'creates an invoice' do
            result = invoice_service.create

            aggregate_failures do
              expect(result).to be_success

              expect(result.invoice.fees.first.properties['to_date']).to eq('2022-04-05')
              expect(result.invoice.fees.first.properties['from_date']).to eq('2022-03-06')
              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.issuing_date.to_date).to eq(timestamp)
              expect(result.invoice.invoice_type).to eq('subscription')
              expect(result.invoice.status).to eq('pending')
              expect(result.invoice.fees.subscription_kind.count).to eq(1)
              expect(result.invoice.fees.charge_kind.count).to eq(0)

              expect(result.invoice.amount_cents).to eq(100)
              expect(result.invoice.amount_currency).to eq('EUR')
              expect(result.invoice.vat_amount_cents).to eq(20)
              expect(result.invoice.vat_amount_currency).to eq('EUR')
              expect(result.invoice.vat_rate).to eq(20)
              expect(result.invoice.credit_amount_cents).to eq(0)
              expect(result.invoice.credit_amount_currency).to eq('EUR')
              expect(result.invoice.total_amount_cents).to eq(120)
              expect(result.invoice.total_amount_currency).to eq('EUR')

              expect(result.invoice).to be_legacy
            end
          end
        end
      end
    end

    context 'when billed monthly and two subscriptions are given' do
      let(:subscription2) do
        create(
          :subscription,
          plan: plan,
          customer: subscription.customer,
          subscription_date: (Time.zone.now - 2.years).to_date,
          started_at: Time.zone.now - 2.years,
        )
      end
      let(:subscriptions) { [subscription, subscription2] }

      it 'creates an invoice for both subscriptions' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_date']).to eq (timestamp - 1.day).to_date.to_s
          expect(result.invoice.fees.first.properties['from_date']).to eq (timestamp - 1.month).to_date.to_s
          expect(result.invoice.subscriptions).to eq(subscriptions)
          expect(result.invoice.issuing_date.to_date).to eq(timestamp)
          expect(result.invoice.invoice_type).to eq('subscription')
          expect(result.invoice.status).to eq('pending')
          expect(result.invoice.fees.subscription_kind.count).to eq(2)
          expect(result.invoice.fees.charge_kind.count).to eq(2)

          expect(result.invoice.amount_cents).to eq(200)
          expect(result.invoice.amount_currency).to eq('EUR')
          expect(result.invoice.vat_amount_cents).to eq(40)
          expect(result.invoice.vat_amount_currency).to eq('EUR')
          expect(result.invoice.vat_rate).to eq(20)
          expect(result.invoice.credit_amount_cents).to eq(0)
          expect(result.invoice.credit_amount_currency).to eq('EUR')
          expect(result.invoice.total_amount_cents).to eq(240)
          expect(result.invoice.total_amount_currency).to eq('EUR')

          expect(result.invoice).to be_legacy
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
          subscription_date: started_at.to_date,
          started_at: started_at,
          created_at: started_at,
        )
      end

      let(:plan) do
        create(:plan, interval: 'monthly')
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_date']).to eq (timestamp - 1.day).to_date.to_s
          expect(result.invoice.fees.first.properties['from_date']).to eq subscription.subscription_date.to_date.to_s
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end
    end

    context 'when billed weekly' do
      let(:timestamp) { Time.zone.now.beginning_of_week }

      let(:plan) do
        create(:plan, interval: 'weekly', pay_in_advance: pay_in_advance)
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_date']).to eq (timestamp - 1.day).to_date.to_s
          expect(result.invoice.fees.first.properties['from_date']).to eq (timestamp - 1.week).to_date.to_s
          subscription.subscription_date
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end

      context 'when subscription is billed on anniversary date' do
        let(:timestamp) { DateTime.parse('07 Mar 2022') }
        let(:started_at) { DateTime.parse('06 Jun 2021').to_date }
        let(:subscription_date) { started_at }

        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            subscription_date: subscription_date,
            started_at: started_at,
            billing_time: :anniversary,
            created_at: started_at,
          )
        end

        it 'creates an invoice' do
          result = invoice_service.create

          aggregate_failures do
            expect(result).to be_success

            expect(result.invoice.fees.first.properties['to_date']).to eq('2022-03-05')
            expect(result.invoice.fees.first.properties['from_date']).to eq('2022-02-27')
            subscription.subscription_date
            expect(result.invoice.subscriptions.first).to eq(subscription)
            expect(result.invoice.fees.subscription_kind.count).to eq(1)
            expect(result.invoice.fees.charge_kind.count).to eq(1)
          end
        end

        context 'when plan is pay in advance' do
          let(:pay_in_advance) { true }

          it 'creates an invoice' do
            result = invoice_service.create

            aggregate_failures do
              expect(result).to be_success

              expect(result.invoice.fees.first.properties['to_date']).to eq('2022-03-12')
              expect(result.invoice.fees.first.properties['from_date']).to eq('2022-03-06')
              subscription.subscription_date
              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.fees.subscription_kind.count).to eq(1)
              expect(result.invoice.fees.charge_kind.count).to eq(0)
            end
          end
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
          created_at: started_at,
        )
      end

      let(:plan) do
        create(:plan, interval: 'weekly')
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_date']).to eq (timestamp - 1.day).to_date.to_s
          expect(result.invoice.fees.first.properties['from_date']).to eq subscription.subscription_date.to_date.to_s
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end
    end

    context 'when billed yearly' do
      let(:timestamp) { Time.zone.now.beginning_of_year }

      let(:plan) do
        create(:plan, interval: 'yearly', pay_in_advance: pay_in_advance)
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_date']).to eq (timestamp - 1.day).to_date.to_s
          expect(result.invoice.fees.first.properties['from_date']).to eq (timestamp - 1.year).to_date.to_s
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
            described_class.new(subscriptions: [subscription], timestamp: first_invoice_timestamp).create
          end

          let(:timestamp) { (subscription.started_at.end_of_year + 1.month + 1.day).to_i }

          it 'creates an invoice for charges' do
            result = invoice_service.create

            aggregate_failures do
              expect(result).to be_success

              expect(result.invoice.fees.subscription_kind.count).to eq(0)
              expect(result.invoice.fees.charge_kind.count).to eq(1)
              expect(result.invoice.fees.first.properties['charges_from_date'])
                .to eq (Time.zone.at(timestamp).to_date - 1.month).to_s
            end
          end
        end
      end

      context 'when subscription is billed on anniversary date' do
        let(:timestamp) { DateTime.parse('07 Jun 2022') }
        let(:started_at) { DateTime.parse('06 Jun 2020').to_date }
        let(:subscription_date) { started_at }

        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            subscription_date: subscription_date,
            started_at: started_at,
            billing_time: :anniversary,
            created_at: started_at,
          )
        end

        it 'creates an invoice' do
          result = invoice_service.create

          aggregate_failures do
            expect(result).to be_success

            expect(result.invoice.fees.first.properties['to_date']).to eq('2022-06-05')
            expect(result.invoice.fees.first.properties['from_date']).to eq('2021-06-06')
            subscription.subscription_date
            expect(result.invoice.subscriptions.first).to eq(subscription)
            expect(result.invoice.fees.subscription_kind.count).to eq(1)
            expect(result.invoice.fees.charge_kind.count).to eq(1)
          end
        end

        context 'when plan is pay in advance' do
          let(:pay_in_advance) { true }

          it 'creates an invoice' do
            result = invoice_service.create

            aggregate_failures do
              expect(result).to be_success

              expect(result.invoice.fees.first.properties['to_date']).to eq('2023-06-05')
              expect(result.invoice.fees.first.properties['from_date']).to eq('2022-06-06')
              subscription.subscription_date
              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.fees.subscription_kind.count).to eq(1)
              expect(result.invoice.fees.charge_kind.count).to eq(0)
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
          created_at: started_at,
        )
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_date']).to eq (timestamp - 1.day).to_date.to_s
          expect(result.invoice.fees.first.properties['from_date']).to eq subscription.subscription_date.to_date.to_s
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
          created_at: started_at,
        )
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result.invoice.issuing_date).to eq(timestamp)
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
          created_at: started_at,
        )
      end

      it 'creates an invoice with subscription fee' do
        result = invoice_service.create

        aggregate_failures do
          expect(result.invoice.fees.first.properties['to_date'])
            .to eq(terminated_at.to_date.to_s)
          expect(result.invoice.fees.first.properties['from_date'])
            .to eq(terminated_at.to_date.beginning_of_month.to_s)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
        end
      end

      context 'when subscription is billed on anniversary date' do
        let(:timestamp) { DateTime.parse('07 Mar 2022') }
        let(:started_at) { DateTime.parse('06 Jun 2021').to_date }
        let(:subscription_date) { started_at }

        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            subscription_date: subscription_date,
            started_at: started_at,
            status: :terminated,
            billing_time: :anniversary,
            terminated_at: terminated_at,
            created_at: started_at,
          )
        end

        it 'creates an invoice with subscription fee' do
          result = invoice_service.create

          aggregate_failures do
            expect(result.invoice.fees.first.properties['to_date'])
              .to eq(terminated_at.to_date.to_s)
            expect(result.invoice.fees.first.properties['from_date'])
              .to eq('2022-03-06')
            expect(result.invoice.fees.subscription_kind.count).to eq(1)
          end
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
      let(:previous_plan) { create(:plan, amount_cents: 10_000, interval: :yearly, pay_in_advance: true) }

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
          created_at: terminated_at + 1.day,
        )
      end

      before { subscription }

      it 'creates an invoice with pro-rated charge fee and without charge fees' do
        result = invoice_service.create

        aggregate_failures do
          expect(result.invoice.fees.first.properties['to_date'])
            .to eq(subscription.started_at.to_date.end_of_month.to_s)
          expect(result.invoice.fees.first.properties['from_date'])
            .to eq(subscription.started_at.to_date.to_s)
          expect(result.invoice.total_amount_cents).to eq(81)
          expect(result.invoice).to be_pending
          expect(result.invoice.fees.charge_kind.count).to eq(0)
        end
      end
    end

    context 'when subscription is pay in advance and terminated after upgrade' do
      let(:plan) do
        create(:plan, interval: :monthly, pay_in_advance: true, amount_cents: 1000)
      end
      let(:next_subscription) do
        create(
          :subscription,
          plan: next_plan,
          subscription_date: started_at.to_date,
          started_at: terminated_at,
          status: :active,
          billing_time: :calendar,
          previous_subscription: subscription,
          customer: subscription.customer,
        )
      end

      let(:started_at) { DateTime.parse('07 Mar 2022') }
      let(:terminated_at) { DateTime.parse('17 Oct 2022') }
      let(:timestamp) { DateTime.parse('17 Oct 2022') }

      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_date: started_at.to_date,
          started_at: started_at,
          status: :terminated,
          terminated_at: terminated_at,
          billing_time: :calendar,
        )
      end

      let(:next_plan) { create(:plan, interval: :monthly, amount_cents: 2000) }

      let(:charge) do
        create(:standard_charge, plan: plan, properties: { amount: 100 })
      end

      before { next_subscription }

      it 'creates an invoice with only the charge fees' do
        result = invoice_service.create

        aggregate_failures do
          expect(result.invoice.fees.subscription_kind.count).to eq(0)
          expect(result.invoice.fees.charge_kind.count).to eq(1)

          charge_fee = result.invoice.fees.charge_kind.first
          expect(charge_fee.properties['charges_from_date']).to eq('2022-10-01')
          expect(charge_fee.properties['charges_to_date']).to eq('2022-10-17')
        end
      end
    end

    context 'with credit' do
      let(:credit_note) do
        create(
          :credit_note,
          customer: subscription.customer,
          total_amount_cents: 10,
          total_amount_currency: plan.amount_currency,
          balance_amount_cents: 10,
          balance_amount_currency: plan.amount_currency,
          credit_amount_cents: 10,
          credit_amount_currency: plan.amount_currency,
        )
      end

      before { credit_note }

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.amount_cents).to eq(100)
          expect(result.invoice.amount_currency).to eq('EUR')
          expect(result.invoice.vat_amount_cents).to eq(20)
          expect(result.invoice.vat_amount_currency).to eq('EUR')
          expect(result.invoice.vat_rate).to eq(20)
          expect(result.invoice.credit_amount_cents).to eq(10)
          expect(result.invoice.credit_amount_currency).to eq('EUR')
          expect(result.invoice.total_amount_cents).to eq(110)
          expect(result.invoice.total_amount_currency).to eq('EUR')

          expect(result.invoice.credits.count).to eq(1)

          expect(result.invoice).to be_legacy

          credit = result.invoice.credits.first
          expect(credit.credit_note).to eq(credit_note)
          expect(credit.amount_cents).to eq(10)
          expect(credit.amount_currency).to eq('EUR')
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

          expect(result.invoice.fees.first.properties['to_date']).to eq (timestamp - 1.day).to_date.to_s
          expect(result.invoice.fees.first.properties['from_date']).to eq (timestamp - 1.month).to_date.to_s
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.issuing_date.to_date).to eq(timestamp)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)

          expect(result.invoice.amount_cents).to eq(100)
          expect(result.invoice.amount_currency).to eq('EUR')
          expect(result.invoice.vat_amount_cents).to eq(20)
          expect(result.invoice.vat_amount_currency).to eq('EUR')
          expect(result.invoice.vat_rate).to eq(20)
          expect(result.invoice.credit_amount_cents).to eq(10)
          expect(result.invoice.credit_amount_currency).to eq('EUR')
          expect(result.invoice.total_amount_cents).to eq(110)
          expect(result.invoice.total_amount_currency).to eq('EUR')

          expect(result.invoice).to be_legacy

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

    context 'with applied prepaid credits' do
      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:wallet) { create(:wallet, customer: subscription.customer, balance: '0.30', credits_balance: '0.30') }

      let(:plan) do
        create(:plan, interval: 'monthly')
      end

      before { wallet }

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_date']).to eq (timestamp - 1.day).to_date.to_s
          expect(result.invoice.fees.first.properties['from_date']).to eq (timestamp - 1.month).to_date.to_s
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.issuing_date.to_date).to eq(timestamp)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)

          expect(result.invoice.amount_cents).to eq(100)
          expect(result.invoice.amount_currency).to eq('EUR')
          expect(result.invoice.vat_amount_cents).to eq(20)
          expect(result.invoice.vat_amount_currency).to eq('EUR')
          expect(result.invoice.vat_rate).to eq(20)
          expect(result.invoice.credit_amount_cents).to eq(30)
          expect(result.invoice.credit_amount_currency).to eq('EUR')
          expect(result.invoice.total_amount_cents).to eq(90)
          expect(result.invoice.total_amount_currency).to eq('EUR')

          expect(result.invoice).to be_legacy

          expect(result.invoice.wallet_transactions.count).to eq(1)
        end
      end

      it 'updates wallet balance' do
        invoice_service.create

        expect(wallet.reload.balance).to eq(0.0)
      end

      context 'when invoice amount in cents is zero' do
        let(:applied_coupon) do
          create(
            :applied_coupon,
            customer: subscription.customer,
            amount_cents: 120,
            amount_currency: plan.amount_currency,
          )
        end

        before { applied_coupon }

        it 'does not create any wallet transactions' do
          result = invoice_service.create

          expect(result.invoice.wallet_transactions.exists?).to be(false)
        end
      end
    end
  end
end
