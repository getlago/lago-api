# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LifetimeUsages::RecalculateAndCheckService, type: :service do
  subject(:service) { described_class.new(lifetime_usage:) }

  let(:lifetime_usage) { create(:lifetime_usage, subscription:, recalculate_current_usage:, recalculate_invoiced_usage:) }
  let(:recalculate_current_usage) { true }
  let(:recalculate_invoiced_usage) { true }
  let(:subscription) { create(:subscription, customer_id: customer.id) }
  let(:organization) { subscription.organization }
  let(:customer) { create(:customer) }

  let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:, properties: {amount: '10'}) }
  let(:timestamp) { Time.current }

  let(:events) do
    create_list(
      :event,
      2,
      organization:,
      subscription:,
      customer:,
      code: billable_metric.code,
      timestamp:
    )
  end

  def create_thresholds(subscription, amounts:, recurring: nil)
    amounts.each do |amount|
      subscription.plan.usage_thresholds.create!(amount_cents: amount)
    end
    if recurring
      subscription.plan.usage_thresholds.create!(amount_cents: recurring, recurring: true)
    end
  end

  context "when we pass a threshold" do
    let(:usage_threshold) { create(:usage_threshold, plan: subscription.plan, amount_cents: 10) }

    before do
      usage_threshold
      events
      charge
    end

    it "clears the recalculate_invoiced_usage flag" do
      expect { service.call }.to change(lifetime_usage, :recalculate_invoiced_usage).from(true).to(false)
    end

    it "clears the recalculate_current_usage flag" do
      expect { service.call }.to change(lifetime_usage, :recalculate_current_usage).from(true).to(false)
    end

    it "sends a webhook for that threshold" do
      expect { service.call }.to enqueue_job(SendWebhookJob)
        .with(
          'subscription.usage_threshold_reached',
          subscription,
          usage_threshold:
        ).on_queue(:webhook)
    end

    it "creates an invoice for the usage_threshold" do
      expect { service.call }.to change(Invoice, :count).by(1)
    end

    context 'when there is tax provider error' do
      let(:error_result) { BaseService::Result.new.service_failure!(code: 'tax_error', message: '') }

      before do
        allow(Invoices::ProgressiveBillingService).to receive(:call).and_return(error_result)
      end

      it "creates a failed invoice without raising error" do
        expect { service.call }.not_to raise_error
      end
    end
  end

  context "when we pass multiple thresholds" do
    let(:usage_threshold) { create(:usage_threshold, plan: subscription.plan, amount_cents: 10) }
    let(:usage_threshold2) { create(:usage_threshold, plan: subscription.plan, amount_cents: 400) }

    before do
      usage_threshold
      usage_threshold2
      events
      charge
    end

    it "clears the recalculate_invoiced_usage flag" do
      expect { service.call }.to change(lifetime_usage, :recalculate_invoiced_usage).from(true).to(false)
    end

    it "clears the recalculate_current_usage flag" do
      expect { service.call }.to change(lifetime_usage, :recalculate_current_usage).from(true).to(false)
    end

    it "sends a webhook for the first threshold" do
      expect { service.call }.to enqueue_job(SendWebhookJob)
        .with(
          'subscription.usage_threshold_reached',
          subscription,
          usage_threshold:
        ).on_queue(:webhook)
    end

    it "sends a webhook for the last threshold" do
      expect { service.call }.to enqueue_job(SendWebhookJob)
        .with(
          'subscription.usage_threshold_reached',
          subscription,
          usage_threshold: usage_threshold2
        ).on_queue(:webhook)
    end

    it "creates an invoice for the current usage" do
      expect { service.call }.to change(Invoice, :count).by(1)
    end
  end

  context "when we pass a threshold with already progressive_billing invoices present" do
    let(:usage_threshold) { create(:usage_threshold, plan: subscription.plan, amount_cents: 10) }
    let(:usage_threshold2) { create(:usage_threshold, plan: subscription.plan, amount_cents: 400) }
    let(:progressive_billing_invoice) do
      create(
        :invoice,
        organization:,
        customer:,
        status: 'finalized',
        invoice_type: :progressive_billing,
        subscriptions: [subscription]
      )
    end

    let(:progressive_billing_fee) { create(:charge_fee, amount_cents: 20, invoice: progressive_billing_invoice) }

    before do
      usage_threshold
      usage_threshold2
      progressive_billing_fee
      events
      charge
    end

    it "clears the recalculate_invoiced_usage flag" do
      expect { service.call }.to change(lifetime_usage, :recalculate_invoiced_usage).from(true).to(false)
    end

    it "clears the recalculate_current_usage flag" do
      expect { service.call }.to change(lifetime_usage, :recalculate_current_usage).from(true).to(false)
    end

    it "sends a webhook for the last threshold" do
      expect { service.call }.to enqueue_job(SendWebhookJob)
        .with(
          'subscription.usage_threshold_reached',
          subscription,
          usage_threshold: usage_threshold2
        ).on_queue(:webhook)
    end

    it "creates an invoice for the current usage" do
      expect { service.call }.to change(Invoice, :count).by(1)
    end
  end

  context "when we pass no thresholds" do
    let(:usage_threshold) { create(:usage_threshold, plan: subscription.plan, amount_cents: 3000) }

    before do
      usage_threshold
      events
      charge
    end

    it "clears the recalculate_invoiced_usage flag" do
      expect { service.call }.to change(lifetime_usage, :recalculate_invoiced_usage).from(true).to(false)
    end

    it "clears the recalculate_current_usage flag" do
      expect { service.call }.to change(lifetime_usage, :recalculate_current_usage).from(true).to(false)
    end

    it "does not send a webhook for the threshold" do
      expect { service.call }.not_to enqueue_job(SendWebhookJob)
        .with(
          'subscription.usage_threshold_reached',
          subscription,
          usage_threshold:
        ).on_queue(:webhook)
    end

    it "does not create an invoice for the largest usage_threshold amount" do
      expect { service.call }.not_to change(Invoice, :count)
      expect(subscription.invoices.progressive_billing).to be_empty
    end
  end
end
