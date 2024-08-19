# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::ProgressiveBillingService, type: :service do
  subject(:create_service) { described_class.new(usage_thresholds:, lifetime_usage:, timestamp:) }

  let(:usage_thresholds) { [create(:usage_threshold, plan:)] }
  let(:plan) { create(:plan) }
  let(:organization) { plan.organization }

  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, plan:, customer:) }
  let(:lifetime_usage) { create(:lifetime_usage, subscription:) }

  let(:timestamp) { Time.current.beginning_of_month }

  let(:tax) { create(:tax, organization:, rate: 20) }

  before do
    allow(SegmentTrackJob).to receive(:perform_later)

    tax
  end

  describe '#call' do
    it 'creates a progressive billing invoice', aggregate_failures: true do
      result = create_service.call

      expect(result).to be_success
      expect(result.invoice).to be_present

      invoice = result.invoice
      usage_threshold = usage_thresholds.first
      expect(invoice).to be_persisted
      expect(invoice).to have_attributes(
        organization: organization,
        customer: customer,
        currency: plan.amount_currency,
        status: 'finalized',
        invoice_type: 'progressive_billing',
        fees_amount_cents: usage_threshold.amount_cents,
        taxes_amount_cents: usage_threshold.amount_cents * tax.rate / 100,
        total_amount_cents: usage_threshold.amount_cents + usage_threshold.amount_cents * tax.rate / 100
      )

      expect(invoice.invoice_subscriptions.count).to eq(1)
      expect(invoice.fees.count).to eq(1)
    end

    context 'with multiple thresholds' do
      let(:usage_thresholds) do
        [
          create(:usage_threshold, plan:, amount_cents: 1000),
          create(:usage_threshold, plan:, amount_cents: 2500)
        ]
      end

      it 'creates a progressive billing invoice with two fees', aggregate_failures: true do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to be_present

        invoice = result.invoice
        expect(invoice).to be_persisted
        expect(invoice).to have_attributes(
          organization: organization,
          customer: customer,
          currency: plan.amount_currency,
          status: 'finalized',
          invoice_type: 'progressive_billing',
          fees_amount_cents: 2500,
          taxes_amount_cents: 2500 * tax.rate / 100,
          total_amount_cents: 2500 * (1 + tax.rate / 100)
        )

        expect(invoice.invoice_subscriptions.count).to eq(1)
        expect(invoice.fees.count).to eq(2)

        expect(invoice.fees.pluck(:amount_cents)).to match_array([1000, 1500])
        expect(invoice.fees.pluck(:usage_threshold_id)).to match_array(usage_thresholds.map(&:id))
      end

      context 'with a recurring threshold' do
        let(:usage_thresholds) do
          # NOTE: the order is wrong on purpose to test the sorting
          [
            create(:usage_threshold, plan:, amount_cents: 2500),
            create(:usage_threshold, :recurring, plan:, amount_cents: 500),
            create(:usage_threshold, plan:, amount_cents: 1000)
          ]
        end

        let(:lifetime_usage) { create(:lifetime_usage, subscription:, current_usage_amount_cents: 4300) }

        it 'creates a progressive billing invoice with multiples fees', aggregate_failures: true do
          result = create_service.call

          expect(result).to be_success
          expect(result.invoice).to be_present

          invoice = result.invoice
          expect(invoice).to be_persisted
          expect(invoice).to have_attributes(
            organization: organization,
            customer: customer,
            currency: plan.amount_currency,
            status: 'finalized',
            invoice_type: 'progressive_billing',
            fees_amount_cents: 4000,
            taxes_amount_cents: 4000 * tax.rate / 100,
            total_amount_cents: 4000 * (1 + tax.rate / 100)
          )

          expect(invoice.invoice_subscriptions.count).to eq(1)
          expect(invoice.fees.count).to eq(3)

          expect(invoice.fees.pluck(:amount_cents)).to match_array([1000, 1500, 1500])
          expect(invoice.fees.pluck(:usage_threshold_id)).to match_array(usage_thresholds.map(&:id))
          expect(invoice.fees.pluck(:units)).to match_array([1, 1, 3])
        end
      end
    end

    context 'when threshold was already billed' do
      before do
        create(
          :invoice,
          organization:,
          customer:,
          status: 'finalized',
          invoice_type: :progressive_billing,
          fees_amount_cents: 20,
          subscriptions: [subscription]
        )
      end

      it 'creates a progressive billing invoice', aggregate_failures: true do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to be_present

        invoice = result.invoice
        usage_threshold = usage_thresholds.first
        amount_cents = usage_threshold.amount_cents - 20

        expect(invoice).to be_persisted
        expect(invoice).to have_attributes(
          organization: organization,
          customer: customer,
          currency: plan.amount_currency,
          status: 'finalized',
          invoice_type: 'progressive_billing',
          fees_amount_cents: amount_cents,
          taxes_amount_cents: amount_cents * tax.rate / 100,
          total_amount_cents: amount_cents * (1 + tax.rate / 100)
        )

        expect(invoice.invoice_subscriptions.count).to eq(1)
        expect(invoice.fees.count).to eq(1)
      end
    end

    context 'when usage was already billed' do
      before do
        create(
          :invoice,
          organization:,
          customer:,
          status: 'finalized',
          invoice_type: :subscription,
          fees_amount_cents: 7,
          subscriptions: [subscription]
        )
      end

      it 'creates a progressive billing invoice', aggregate_failures: true do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to be_present

        invoice = result.invoice
        usage_threshold = usage_thresholds.first
        amount_cents = usage_threshold.amount_cents - 7

        expect(invoice).to be_persisted
        expect(invoice).to have_attributes(
          organization: organization,
          customer: customer,
          currency: plan.amount_currency,
          status: 'finalized',
          invoice_type: 'progressive_billing',
          fees_amount_cents: amount_cents,
          taxes_amount_cents: (amount_cents * tax.rate / 100).round,
          total_amount_cents: (amount_cents * (1 + tax.rate / 100)).round
        )

        expect(invoice.invoice_subscriptions.count).to eq(1)
        expect(invoice.fees.count).to eq(1)
      end

      context 'with a recurring threshold' do
        let(:usage_thresholds) { [create(:usage_threshold, :recurring, plan:, amount_cents: 100)] }

        let(:lifetime_usage) { create(:lifetime_usage, subscription:, current_usage_amount_cents: 215) }

        it 'creates a progressive billing invoice', aggregate_failures: true do
          result = create_service.call

          expect(result).to be_success
          expect(result.invoice).to be_present

          invoice = result.invoice
          usage_threshold = usage_thresholds.first
          amount_cents = usage_threshold.amount_cents * 2

          expect(invoice).to be_persisted
          expect(invoice).to have_attributes(
            organization: organization,
            customer: customer,
            currency: plan.amount_currency,
            status: 'finalized',
            invoice_type: 'progressive_billing',
            fees_amount_cents: amount_cents,
            taxes_amount_cents: amount_cents * tax.rate / 100,
            total_amount_cents: amount_cents * (1 + tax.rate / 100)
          )

          expect(invoice.invoice_subscriptions.count).to eq(1)
          expect(invoice.fees.count).to eq(1)

          expect(invoice.fees.pluck(:units)).to match_array([2])
        end
      end
    end

    it 'enqueues a SendWebhookJob' do
      expect { create_service.call }.to have_enqueued_job(SendWebhookJob)
    end

    it 'enqueue an GeneratePdfAndNotifyJob with email false' do
      expect { create_service.call }
        .to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: false))
    end

    context 'with lago_premium' do
      around { |test| lago_premium!(&test) }

      it 'enqueues an GeneratePdfAndNotifyJob with email true' do
        expect { create_service.call }
          .to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: true))
      end

      context 'when organization does not have right email settings' do
        before { organization.update!(email_settings: []) }

        it 'enqueue an GeneratePdfAndNotifyJob with email false' do
          expect { create_service.call }
            .to have_enqueued_job(Invoices::GeneratePdfAndNotifyJob).with(hash_including(email: false))
        end
      end
    end

    it 'calls SegmentTrackJob' do
      invoice = create_service.call.invoice

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type
        }
      )
    end

    it 'creates a payment' do
      allow(Invoices::Payments::CreateService).to receive(:call)

      create_service.call

      expect(Invoices::Payments::CreateService).to have_received(:call)
    end

    it_behaves_like 'syncs invoice' do
      let(:service_call) { create_service.call }
    end

    it_behaves_like 'syncs sales order' do
      let(:service_call) { create_service.call }
    end
  end
end
