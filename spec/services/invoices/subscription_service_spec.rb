# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::SubscriptionService, type: :service do
  subject(:invoice_service) do
    described_class.new(
      subscriptions:,
      timestamp: timestamp.to_i,
      recurring: true,
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, organization:, rate: 20) }

  describe 'call' do
    let(:subscription) do
      create(
        :subscription,
        plan:,
        customer:,
        subscription_at: started_at.to_date,
        started_at:,
        created_at: started_at,
      )
    end
    let(:subscriptions) { [subscription] }

    let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
    let(:timestamp) { Time.zone.now.beginning_of_month }
    let(:started_at) { Time.zone.now - 2.years }

    let(:plan) { create(:plan, interval: 'monthly', pay_in_advance:) }
    let(:pay_in_advance) { false }

    before do
      tax
      create(:standard_charge, plan: subscription.plan, charge_model: 'standard')

      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::Payments::StripeCreateJob).to receive(:perform_later).and_call_original
      allow(Invoices::Payments::GocardlessCreateJob).to receive(:perform_later).and_call_original
    end

    it 'calls SegmentTrackJob' do
      invoice = invoice_service.call.invoice

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

    it 'creates a payment' do
      payment_create_service = instance_double(Invoices::Payments::CreateService)
      allow(Invoices::Payments::CreateService)
        .to receive(:new).and_return(payment_create_service)
      allow(payment_create_service)
        .to receive(:call)

      invoice_service.call

      expect(Invoices::Payments::CreateService).to have_received(:new)
      expect(payment_create_service).to have_received(:call)
    end

    it 'creates an invoice' do
      result = invoice_service.call

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice.invoice_subscriptions.first.to_datetime)
          .to match_datetime((timestamp - 1.day).end_of_day)
        expect(result.invoice.invoice_subscriptions.first.from_datetime)
          .to match_datetime((timestamp - 1.month).beginning_of_day)

        expect(result.invoice.subscriptions.first).to eq(subscription)
        expect(result.invoice.issuing_date.to_date).to eq(timestamp)
        expect(result.invoice.invoice_type).to eq('subscription')
        expect(result.invoice.payment_status).to eq('pending')
        expect(result.invoice.fees.subscription_kind.count).to eq(1)
        expect(result.invoice.fees.charge_kind.count).to eq(1)

        expect(result.invoice.currency).to eq('EUR')
        expect(result.invoice.fees_amount_cents).to eq(100)

        expect(result.invoice.taxes_amount_cents).to eq(20)
        expect(result.invoice.taxes_rate).to eq(20)
        expect(result.invoice.applied_taxes.count).to eq(1)

        expect(result.invoice.total_amount_cents).to eq(120)
        expect(result.invoice.version_number).to eq(4)
        expect(result.invoice).to be_finalized
      end
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        invoice_service.call
      end.to have_enqueued_job(SendWebhookJob).with('invoice.created', Invoice)
    end

    it 'does not enqueue an ActionMailer::MailDeliveryJob' do
      expect do
        invoice_service.call
      end.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
    end

    context 'when recurring but no active subscriptions' do
      it 'does not create any invoices' do
        subscription.terminated!
        expect { invoice_service.call }.not_to change(Invoice, :count)
      end
    end

    context 'with lago_premium' do
      around { |test| lago_premium!(&test) }

      it 'enqueues an ActionMailer::MailDeliveryJob' do
        expect do
          invoice_service.call
        end.to have_enqueued_job(ActionMailer::MailDeliveryJob)
      end

      context 'when organization does not have right email settings' do
        before { subscription.customer.organization.update!(email_settings: []) }

        it 'does not enqueue an ActionMailer::MailDeliveryJob' do
          expect do
            invoice_service.call
          end.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
        end
      end
    end

    context 'when organization does not have a webhook endpoint' do
      before { subscription.customer.organization.webhook_endpoints.destroy_all }

      it 'does not enqueue a SendWebhookJob' do
        expect do
          invoice_service.call
        end.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'with customer timezone' do
      before { subscription.customer.update!(timezone: 'America/Los_Angeles', invoice_grace_period: 3) }

      let(:timestamp) { DateTime.parse('2022-11-25 01:00:00') }

      it 'assigns the issuing date in the customer timezone' do
        result = invoice_service.call

        expect(result.invoice.issuing_date.to_s).to eq('2022-11-27')
      end
    end

    context 'with applicable grace period' do
      before do
        subscription.customer.update!(invoice_grace_period: 3)
      end

      it 'does not track any invoice creation on segment' do
        invoice_service.call
        expect(SegmentTrackJob).not_to have_received(:perform_later)
      end

      it 'does not create any payment' do
        invoice_service.call
        expect(Invoices::Payments::StripeCreateJob).not_to have_received(:perform_later)
        expect(Invoices::Payments::GocardlessCreateJob).not_to have_received(:perform_later)
      end

      it 'creates an invoice as draft' do
        result = invoice_service.call
        expect(result).to be_success
        expect(result.invoice).to be_draft
      end

      it 'enqueues a SendWebhookJob' do
        expect do
          invoice_service.call
        end.to have_enqueued_job(SendWebhookJob).with('invoice.drafted', Invoice)
      end
    end
  end
end
