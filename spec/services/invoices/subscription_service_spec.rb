# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::SubscriptionService do
  subject(:invoice_service) do
    described_class.new(
      subscriptions:,
      timestamp: timestamp.to_i,
      invoicing_reason:
    )
  end

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:customer) { create(:customer, organization:, billing_entity:) }
  let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 20, billing_entity:) }

  let(:invoicing_reason) { :subscription_periodic }

  describe "#call" do
    let(:subscription) do
      create(
        :subscription,
        plan:,
        customer:,
        subscription_at: started_at.to_date,
        started_at:,
        created_at: started_at
      )
    end
    let(:subscriptions) { [subscription] }
    let(:lifetime_usage) { create(:lifetime_usage, subscription: subscription) }

    let(:billable_metric) { create(:billable_metric, aggregation_type: "count_agg") }
    let(:timestamp) { Time.zone.now.beginning_of_month }
    let(:started_at) { Time.zone.parse("2022-10-01T00:00:00.000Z") }

    let(:plan) { create(:plan, interval: "monthly", pay_in_advance:) }
    let(:pay_in_advance) { false }

    before do
      tax
      create(:standard_charge, plan: subscription.plan, charge_model: "standard")
      lifetime_usage

      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::Payments::CreateService).to receive(:call_async).and_call_original
      allow(Invoices::TransitionToFinalStatusService).to receive(:call).and_call_original
    end

    it "calls SegmentTrackJob" do
      invoice = invoice_service.call.invoice

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: "invoice_created",
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type
        }
      )
    end

    it "creates a payment" do
      allow(Invoices::Payments::CreateService).to receive(:call_async)

      invoice_service.call

      expect(Invoices::Payments::CreateService).to have_received(:call_async)
    end

    it "creates an invoice" do
      result = invoice_service.call

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice.invoice_subscriptions.first.to_datetime)
          .to match_datetime((timestamp - 1.day).end_of_day)
        expect(result.invoice.invoice_subscriptions.first.from_datetime)
          .to match_datetime((timestamp - 1.month).beginning_of_day)

        expect(result.invoice.subscriptions.first).to eq(subscription)
        expect(result.invoice.issuing_date.to_date).to eq(timestamp)
        expect(result.invoice.invoice_type).to eq("subscription")
        expect(result.invoice.payment_status).to eq("pending")
        expect(result.invoice.fees.subscription.count).to eq(1)
        expect(result.invoice.fees.charge.count).to eq(0)

        expect(result.invoice.currency).to eq("EUR")
        expect(result.invoice.fees_amount_cents).to eq(100)

        expect(result.invoice.taxes_amount_cents).to eq(20)
        expect(result.invoice.taxes_rate).to eq(20)
        expect(result.invoice.applied_taxes.count).to eq(1)

        expect(result.invoice.total_amount_cents).to eq(120)
        expect(result.invoice.version_number).to eq(4)
        expect(Invoices::TransitionToFinalStatusService).to have_received(:call).with(invoice: result.invoice)
        expect(result.invoice).to be_finalized
      end
    end

    it_behaves_like "syncs invoice" do
      let(:service_call) { invoice_service.call }
    end

    it_behaves_like "applies invoice_custom_sections" do
      let(:service_call) { invoice_service.call }
    end

    it "enqueues a SendWebhookJob" do
      expect do
        invoice_service.call
      end.to have_enqueued_job_after_commit(SendWebhookJob).with("invoice.created", Invoice)
    end

    it "produces an activity log" do
      invoice = described_class.call(subscriptions:, timestamp: timestamp.to_i, invoicing_reason:).invoice

      expect(Utils::ActivityLog).to have_produced("invoice.created").after_commit.with(invoice)
    end

    it "enqueues GenerateDocumentsJob with email false" do
      expect do
        invoice_service.call
      end.to have_enqueued_job_after_commit(Invoices::GenerateDocumentsJob).with(hash_including(notify: false))
    end

    it "flags lifetime usage for refresh" do
      create(:usage_threshold, plan:)

      invoice_service.call

      expect(subscription.reload.lifetime_usage.recalculate_invoiced_usage).to be(true)
    end

    context "when there is tax provider integration" do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:) }

      before do
        integration_customer
      end

      it "creates an invoice with pending status and without applied taxes" do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.issuing_date.to_date).to eq(timestamp)
          expect(result.invoice.invoice_type).to eq("subscription")
          expect(result.invoice.payment_status).to eq("pending")
          expect(result.invoice.fees.subscription.count).to eq(1)
          expect(result.invoice.fees.charge.count).to eq(0)

          expect(result.invoice.currency).to eq("EUR")
          expect(result.invoice.fees_amount_cents).to eq(100)

          expect(result.invoice.taxes_amount_cents).to eq(0)
          expect(result.invoice.taxes_rate).to eq(0)
          expect(result.invoice.applied_taxes.count).to eq(0)

          expect(result.invoice.version_number).to eq(4)
          expect(result.invoice).to be_pending
        end
      end
    end

    context "when periodic but no active subscriptions" do
      it "does not create any invoices" do
        subscription.terminated!
        expect { invoice_service.call }.not_to change(Invoice, :count)
      end
    end

    context "with lago_premium" do
      around { |test| lago_premium!(&test) }

      context "when there is a hubspot integration" do
        let(:integration) { create(:hubspot_integration, organization:, sync_invoices:) }
        let(:integration_customer) { create(:hubspot_customer, integration:, customer:) }

        before { integration_customer }

        context "when sync invoices is true" do
          let(:sync_invoices) { true }

          it "enqueues Integrations::Aggregator::Invoices::Hubspot::CreateJob" do
            expect do
              invoice_service.call
            end.to have_enqueued_job_after_commit(Integrations::Aggregator::Invoices::Hubspot::CreateJob)
          end
        end

        context "when sync invoices is false" do
          let(:sync_invoices) { false }

          it "does not enqueue Integrations::Aggregator::Invoices::Hubspot::CreateJob" do
            expect do
              invoice_service.call
            end.not_to have_enqueued_job(Integrations::Aggregator::Invoices::Hubspot::CreateJob)
          end
        end
      end

      context "when there is a netsuite integration" do
        let(:integration) { create(:netsuite_integration, organization:, sync_invoices:) }
        let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }

        before { integration_customer }

        context "when sync invoices is true" do
          let(:sync_invoices) { true }

          it "enqueues Integrations::Aggregator::Invoices::CreateJob" do
            expect do
              invoice_service.call
            end.to have_enqueued_job_after_commit(Integrations::Aggregator::Invoices::CreateJob)
          end
        end

        context "when sync invoices is false" do
          let(:sync_invoices) { false }

          it "does not enqueue Integrations::Aggregator::Invoices::CreateJob" do
            expect do
              invoice_service.call
            end.not_to have_enqueued_job(Integrations::Aggregator::Invoices::CreateJob)
          end
        end
      end

      it "enqueues GenerateDocumentsJob with email true" do
        expect do
          invoice_service.call
        end.to have_enqueued_job_after_commit(Invoices::GenerateDocumentsJob).with(hash_including(notify: true))
      end

      context "when organization does not have right email settings" do
        before { customer.billing_entity.update!(email_settings: []) }

        it "enqueues GenerateDocumentsJob with email false" do
          expect do
            invoice_service.call
          end.to have_enqueued_job_after_commit(Invoices::GenerateDocumentsJob).with(hash_including(notify: false))
        end
      end
    end

    context "with customer timezone" do
      before { subscription.customer.update!(timezone: "America/Los_Angeles", invoice_grace_period: 3) }

      let(:timestamp) { DateTime.parse("2022-11-25 01:00:00") }

      it "assigns the issuing date in the customer timezone" do
        result = invoice_service.call

        expect(result.invoice.issuing_date.to_s).to eq("2022-11-27")
      end
    end

    context "with applicable grace period" do
      before do
        subscription.customer.update!(invoice_grace_period: 3)
      end

      it "does not track any invoice creation on segment" do
        invoice_service.call
        expect(SegmentTrackJob).not_to have_received(:perform_later)
      end

      it "does not create any payment" do
        invoice_service.call
        expect(Invoices::Payments::CreateService).not_to have_received(:call_async)
      end

      it "creates an invoice as draft" do
        result = invoice_service.call
        expect(result).to be_success
        expect(result.invoice).to be_draft
      end

      it "enqueues a SendWebhookJob" do
        expect do
          invoice_service.call
        end.to have_enqueued_job_after_commit(SendWebhookJob).with("invoice.drafted", Invoice)
      end

      it "produces an activity log" do
        invoice = described_class.call(subscriptions:, timestamp: timestamp.to_i, invoicing_reason:).invoice

        expect(Utils::ActivityLog).to have_produced("invoice.drafted").after_commit.with(invoice)
      end

      it "does not flag lifetime usage for refresh" do
        invoice_service.call

        expect(lifetime_usage.reload.recalculate_invoiced_usage).to be(false)
      end

      it "flags wallets for refresh" do
        wallet = create(:wallet, customer:)

        expect { invoice_service.call }.to change { wallet.reload.ready_to_be_refreshed }.from(false).to(true)
      end
    end

    context "when invoice already exists" do
      let(:timestamp) { Time.zone.parse("2023-10-01T00:00:00.000Z") }

      let(:invoice_subscription) do
        create(
          :invoice_subscription,
          invoice: old_invoice,
          subscription:,
          from_datetime: Time.zone.parse("2023-09-01T00:00:00.000Z"),
          to_datetime: Time.zone.parse("2023-09-30T23:59:59.999Z").end_of_day,
          charges_from_datetime: Time.zone.parse("2023-09-01T00:00:00.000Z"),
          charges_to_datetime: Time.zone.parse("2023-09-30T23:59:59.999Z").end_of_day,
          recurring: invoicing_reason.to_sym == :subscription_periodic,
          invoicing_reason:
        )
      end

      let(:old_invoice) do
        create(
          :invoice,
          created_at: timestamp + 1.second,
          customer: subscription.customer
        )
      end

      before { invoice_subscription }

      it "does not raise an error" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice).to be_nil
      end
    end

    context "when skip zero invoices is set" do
      before do
        customer.update(finalize_zero_amount_invoice: :skip)
      end

      context "when invoice total amount is not 0" do
        it "creates an invoice in :finalized status" do
          result = invoice_service.call
          expect(result.invoice.status).to eq("finalized")
          expect(result.invoice.number).not_to include("DRAFT")
        end
      end

      context "when invoice total amount is 0" do
        let(:plan) { create(:plan, interval: "monthly", pay_in_advance:, amount_cents: 0) }

        before do
          plan
        end

        it "creates an invoice in :closed status" do
          result = invoice_service.call
          expect(result.invoice.status).to eq("closed")
          expect(result.invoice.number).to include("DRAFT")
        end

        context "when billing entity has grace period" do
          let(:billing_entity) { create(:billing_entity, organization:, invoice_grace_period: 30) }

          it "creates an invoice in :draft status" do
            result = invoice_service.call
            expect(result.invoice.status).to eq("draft")
          end
        end
      end
    end

    context "when revenue_analytics is set" do
      around { |test| lago_premium!(&test) }

      before do
        organization.update!(premium_integrations: %w[revenue_analytics])
      end

      it "enqueues DailyUsages::FillFromInvoiceJob with email false" do
        expect { invoice_service.call }
          .to have_enqueued_job_after_commit(DailyUsages::FillFromInvoiceJob)
          .with(invoice: an_instance_of(Invoice), subscriptions: [subscription])
      end

      context "when subscription is terminating" do
        let(:invoicing_reason) { :subscription_terminating }

        it "enqueues DailyUsages::FillFromInvoiceJob with email false" do
          expect { invoice_service.call }
            .to have_enqueued_job_after_commit(DailyUsages::FillFromInvoiceJob)
            .with(invoice: an_instance_of(Invoice), subscriptions: [subscription])
        end
      end
    end

    context "when creating invoice for partner" do
      let(:customer) { create(:customer, :with_salesforce_integration, :with_hubspot_integration, organization:, account_type: "partner") }
      let(:salesforce_service) { instance_double(Integrations::Aggregator::Invoices::CreateService) }
      let(:hubspot_service) { instance_double(Integrations::Aggregator::Invoices::Hubspot::CreateService) }
      let(:result) { BaseService::Result.new }

      before do
        allow(Integrations::Aggregator::Invoices::CreateService).to receive(:new).and_return(salesforce_service)
        allow(salesforce_service).to receive(:call).and_return(result)
        allow(Integrations::Aggregator::Invoices::Hubspot::CreateService).to receive(:new).and_return(hubspot_service)
        allow(hubspot_service).to receive(:call).and_return(result)
      end

      it "doesn't send update to integrations" do
        invoice_service.call

        expect(Integrations::Aggregator::Invoices::CreateService).not_to have_received(:new)
        expect(Integrations::Aggregator::Invoices::Hubspot::CreateService).not_to have_received(:new)
      end
    end
  end
end
