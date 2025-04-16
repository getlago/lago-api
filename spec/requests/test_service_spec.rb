# frozen_string_literal: true

require "rails_helper"
require "pry"

RSpec.describe "Custom scenario:", type: :request do
  describe "terminate subscription" do
    subject { Subscriptions::TerminateService.call!(subscription:) }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }

    let(:billable_metric) do
      create(
        :billable_metric,
        organization:,
        code: "advance_recurring",
        name: "Advance Recurring metric",
        aggregation_type: "sum_agg",
        field_name: "prop",
        recurring: true
      ) do |billable_metric|
        create(
          :charge,
          billable_metric:,
          plan:,
          properties: {amount: "10"},
          invoiceable: true,
          prorated: true
        )
      end
    end

    let(:plan) do
      create(:plan, organization:, pay_in_advance: true)
    end

    let!(:subscription) do
      create(
        :subscription,
        organization:,
        customer:,
        plan:,
        subscription_at: Time.zone.parse("2025-02-01"),
        started_at: Time.zone.parse("2025-02-01")
      )
    end

    before do
      allow(SendWebhookJob).to receive(:perform_later)
      allow(SendWebhookJob).to receive(:perform_now)
      allow(SendWebhookJob).to receive_message_chain(:set, :perform_later)
      allow(Invoices::GeneratePdfAndNotifyJob).to receive(:perform_later)
      allow(CreditNotes::GeneratePdfJob).to receive(:perform_later)
      allow(Invoices::Payments::CreateService).to receive(:call_async)
      allow(CreditNoteMailer).to receive_message_chain(:with, :created, :deliver_later)

      travel_to Time.zone.parse("2025-02-15")
    end

    around do |example|
      perform_enqueued_jobs do
        lago_premium!(&example)
      end
    end

    it "creates credit note on termination" do
      BillSubscriptionJob.set(wait: 2.seconds).perform_later(
        [subscription],
        Time.zone.parse("2025-02-01").to_i,
        invoicing_reason: :subscription_starting,
        skip_charges: true
      )

      post_with_token(organization, "/api/v1/events", event: {
        code: billable_metric.code,
        transaction_id: SecureRandom.uuid,
        external_subscription_id: subscription.external_id,
        timestamp: 1.week.ago.to_i,
        precise_total_amount_cents: "123.45",
        properties: {
          prop: 11
        }
      })

      # expect { subject }.to change(CreditNote, :count).by(1)

      # subscription.mark_as_terminated!
      # CreditNotes::CreateFromTermination.call!(
      #   subscription:,
      #   reason: "order_cancellation",
      #   upgrade: false
      # )

      subscription.assign_attributes(
        status: :terminated,
        terminated_at: Time.current
      )

      result = Invoices::Preview::CreditsService.call(
        invoice: Invoice.new(customer:, total_amount_cents: 1000),
        terminated_subscription: subscription
      )

      # expect(CreditNote.first).to have_attributes(attributes)
      # expect(result.credits).to all have_attributes(attributes)
      expect(result.credits).to all have_attributes(amount_cents: 46)
    end
  end

  describe "nango response" do
    subject(:result) { Integrations::Aggregator::Invoices::CreateService.call!(invoice:) }

    let(:invoice) { create(:invoice, customer:, organization:, status: :finalized) }
    let(:organization) { customer.organization }

    let(:customer) { create(:customer) }
    let(:integration) { create(:netsuite_integration, organization:, sync_invoices: true) }
    let!(:integration_customer) do
      create(:netsuite_customer, integration:, customer:)
    end

    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:http_error) { LagoHttpClient::HttpError.new(error_code, body, nil) }
    let(:error_code) { 424 }

    let(:body) do
      {
        error: {
          payload: {
            error: {
              code: "SSS_REQUEST_LIMIT_EXCEEDED",
              message: "Request Limit Exceeded!"
            }
          },
          code: "script_http_error",
          upstream: {
            status: 400,
            headers: {
              "content-type": "application/json;charset=utf-8"
            },
            body: {
              error: {
                code: "SSS_REQUEST_LIMIT_EXCEEDED",
                message: "Request Limit Exceeded!"
              }
            }
          }
        }
      }.to_json
    end

    before do
      allow(LagoHttpClient::Client).to receive(:new).and_return(lago_client)
      allow(lago_client).to receive(:post_with_response).and_raise(http_error)
    end

    around do |example|
      perform_enqueued_jobs do
        lago_premium!(&example)
      end
    end

    it "check handlers" do
      expect { subject }.to raise_exception(Integrations::Aggregator::RequestLimitError)
    end
  end

  describe "min commitments" do
    let(:organization) { create(:organization) }
    let(:plan) { create(:plan, organization:) }
    let(:commitment) { create(:commitment, plan:) }
    let(:customer) { create(:customer, organization:) }

    let(:subscription) do
      create(:subscription, organization:, customer:, plan:, subscription_at: 2.months.ago)
    end

    before do
      allow(SendWebhookJob).to receive(:perform_later)
      allow(Invoices::GeneratePdfAndNotifyJob).to receive(:perform_later)
      allow(Invoices::Payments::CreateService).to receive(:call_async)
    end

    around do |example|
      perform_enqueued_jobs do
        lago_premium!(&example)
      end
    end

    it "run" do
      plan.commitments.find_or_create_by!(
        commitment_type: "minimum_commitment",
        amount_cents: 2000
      )

      # billing_at = Time.current + 1.second
      # BillSubscriptionJob.perform_now(
      #   [subscription],
      #   billing_at.to_i,
      #   invoicing_reason: :subscription_periodic
      # )

      preview = Invoices::PreviewService.call(
        customer:,
        subscriptions: [subscription],
        applied_coupons: []
      ).raise_if_error!

      invoice = preview.invoice

      expect(invoice.fees.find(&:commitment?)).to be_present
    end
  end

  describe "run rec sub" do
    let(:organization) { create(:organization) }

    let(:billable_metric) do
      create(
        :billable_metric,
        organization:,
        code: "advance_recurring",
        name: "Advance Recurring metric",
        aggregation_type: "sum_agg",
        field_name: "prop",
        recurring: true
      ) do |billable_metric|
        create(
          :charge,
          billable_metric:,
          plan:,
          properties: {amount: "10"},
          pay_in_advance: true,
          invoiceable: false,
          prorated: true,
          regroup_paid_fees: "invoice"
        )
      end
    end

    let(:plan) do
      create(
        :plan,
        organization:,
        name: "Advance rec plan",
        code: "advance_rec_plan",
        interval: "monthly",
        amount_cents: 0,
        amount_currency: "USD",
        trial_period: 0.0,
        pay_in_advance: false,
        pending_deletion: false
      )
    end

    let(:customer) do
      create(:customer, organization:, currency: "USD") do |customer|
        customer.taxes << tax
      end
    end

    let(:tax) { create(:tax, organization:, rate: 20.0, code: "fr_20", name: "Fr 20%") }

    let(:subscription) do
      create(
        :subscription,
        plan:,
        customer:,
        status: :active,
        billing_time: "anniversary",
        started_at: 2.months.ago,
        subscription_at: 2.months.from_now
      )
    end

    before do
      allow(SendWebhookJob).to receive(:perform_later)
      allow(Invoices::GeneratePdfAndNotifyJob).to receive(:perform_later)
      allow(Invoices::Payments::CreateService).to receive(:call_async)
    end

    around do |example|
      perform_enqueued_jobs do
        example.run
      end
    end

    it "check" do
      post_with_token(organization, "/api/v1/events", event: {
        code: billable_metric.code,
        transaction_id: SecureRandom.uuid,
        external_subscription_id: subscription.external_id,
        timestamp: 1.month.ago.to_i,
        precise_total_amount_cents: "123.45",
        properties: {
          prop: 11
        }
      })

      Fee.first.update!(payment_status: "succeeded")

      travel_to 1.hour.from_now

      BillSubscriptionJob.perform_now(
        [subscription],
        Time.current.to_i,
        invoicing_reason: :subscription_periodic
      )

      expect(Fee.charge).to all have_attributes(taxes_rate: 20.0)
    end
  end
end
