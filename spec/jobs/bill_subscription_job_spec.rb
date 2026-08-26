# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillSubscriptionJob do
  let(:subscriptions) { [create(:subscription)] }
  let(:timestamp) { Time.zone.now.to_i }

  let(:invoice) { nil }
  let(:invoicing_reason) { :subscription_starting }
  let(:result) { Invoices::SubscriptionService::Result.new }

  # NOTE: when an invoice is given, the job skips term resolution and passes nils
  let(:payment_term) { invoice ? nil : PaymentTerm.from_h({"term_type" => "due_on_receipt"}) }
  let(:payment_term_source) { invoice ? nil : "default" }

  before do
    allow(Invoices::SubscriptionService).to receive(:call)
      .with(subscriptions:, timestamp:, invoicing_reason:, invoice:, skip_charges: false, payment_term:, payment_term_source:)
      .and_return(result)
  end

  describe "#perform" do
    it "calls the invoices create service" do
      described_class.perform_now(subscriptions, timestamp, invoicing_reason:)

      expect(Invoices::SubscriptionService).to have_received(:call)
    end

    context "when result is a failure" do
      let(:result) do
        result = Invoices::SubscriptionService::Result.new
        result.invoice = invoice
        result.single_validation_failure!(error_code: "error")
      end

      it "raises an error" do
        expect do
          described_class.perform_now(subscriptions, timestamp, invoicing_reason:)
        end.to raise_error(BaseService::FailedResult)

        expect(Invoices::SubscriptionService).to have_received(:call)
      end

      context "with a previously created invoice" do
        let(:invoice) { create(:invoice, :generating) }

        it "raises an error" do
          expect do
            described_class.perform_now(subscriptions, timestamp, invoicing_reason:, invoice:)
          end.to raise_error(BaseService::FailedResult)

          expect(Invoices::SubscriptionService).to have_received(:call)
        end

        it "creates an ErrorDetail" do
          expect do
            described_class.perform_now(subscriptions, timestamp, invoicing_reason:, invoice:)
          end.to raise_error(BaseService::FailedResult).and change(invoice.error_details.invoice_generation_error, :count)
            .from(0).to(1)
        end
      end

      context "when a generating invoice is attached to the result" do
        let(:result_invoice) { create(:invoice, :generating) }

        before { result.invoice = result_invoice }

        it "retries the job with the invoice" do
          described_class.perform_now(subscriptions, timestamp, invoicing_reason:)

          expect(Invoices::SubscriptionService).to have_received(:call)

          expect(described_class).to have_been_enqueued
            .with(subscriptions, timestamp, invoicing_reason:, invoice: result_invoice, skip_charges: false)
        end
      end

      context "when a not generating invoice is attached to the result" do
        let(:result_invoice) { create(:invoice, :draft) }

        before { result.invoice = result_invoice }

        it "raises an error" do
          expect do
            described_class.perform_now(subscriptions, timestamp, invoicing_reason:)
          end.to raise_error(BaseService::FailedResult)

          expect(Invoices::SubscriptionService).to have_received(:call)
        end

        it "creates an invoice generation error_detail" do
          expect do
            described_class.perform_now(subscriptions, timestamp, invoicing_reason:)
          end.to raise_error(BaseService::FailedResult)

          expect(ErrorDetail.invoice_generation_error.size).to eq(1)
          expect(result_invoice.error_details.invoice_generation_error.count).to eq(1)
        end
      end
    end
  end

  describe "payment term split" do
    let(:customer) { create(:customer) }
    let(:subscription1) { create(:subscription, customer:) }
    let(:subscription2) { create(:subscription, customer:) }
    let(:subscriptions) { [subscription1, subscription2] }

    let(:net_resolution) do
      PaymentTerms::ResolveService::Result.new.tap do |resolution|
        resolution.payment_term = PaymentTerm.from_h({"term_type" => "net", "days" => 30})
        resolution.source = "customer"
      end
    end

    let(:eom_resolution) do
      PaymentTerms::ResolveService::Result.new.tap do |resolution|
        resolution.payment_term = PaymentTerm.from_h({"term_type" => "end_of_month"})
        resolution.source = "subscription"
      end
    end

    context "when subscriptions resolve to mixed terms" do
      before do
        allow(PaymentTerms::ResolveService).to receive(:call!).and_return(net_resolution, eom_resolution)
        allow(Invoices::SubscriptionService).to receive(:call)
      end

      it "splits into one job per term group without calling the service" do
        described_class.perform_now(subscriptions, timestamp, invoicing_reason:)

        expect(Invoices::SubscriptionService).not_to have_received(:call)
        expect(described_class).to have_been_enqueued
          .with([subscription1], timestamp, invoicing_reason:, skip_charges: false)
        expect(described_class).to have_been_enqueued
          .with([subscription2], timestamp, invoicing_reason:, skip_charges: false)
      end
    end

    context "when subscriptions resolve to the same term with different sources" do
      before do
        allow(PaymentTerms::ResolveService).to receive(:call!).and_return(net_resolution, net_customer_resolution)
        allow(Invoices::SubscriptionService).to receive(:call).and_return(result)
      end

      let(:net_customer_resolution) do
        PaymentTerms::ResolveService::Result.new.tap do |resolution|
          resolution.payment_term = PaymentTerm.from_h({"term_type" => "net", "days" => 30})
          resolution.source = "subscription"
        end
      end

      it "calls the service once with the mixed source" do
        described_class.perform_now(subscriptions, timestamp, invoicing_reason:)

        expect(Invoices::SubscriptionService).to have_received(:call).with(
          subscriptions:,
          timestamp:,
          invoicing_reason:,
          invoice: nil,
          skip_charges: false,
          payment_term: PaymentTerm.from_h({"term_type" => "net", "days" => 30}),
          payment_term_source: "mixed"
        )
        expect(described_class).not_to have_been_enqueued
      end
    end

    context "when an invoice is given" do
      let(:invoice) { create(:invoice, :generating) }

      before { allow(PaymentTerms::ResolveService).to receive(:call!) }

      it "never re-resolves nor splits" do
        described_class.perform_now(subscriptions, timestamp, invoicing_reason:, invoice:)

        expect(PaymentTerms::ResolveService).not_to have_received(:call!)
        expect(Invoices::SubscriptionService).to have_received(:call)
        expect(described_class).not_to have_been_enqueued
      end
    end
  end

  describe "#lock_key_arguments" do
    let(:customer) { create(:customer, timezone: "Europe/Paris") }
    let(:subscription) { create(:subscription, customer:) }
    let(:subscriptions) { [subscription] }

    context "when subscriptions are empty" do
      let(:subscriptions) { [] }
      let(:timestamp) { Time.zone.parse("2024-01-15 10:00:00 UTC").to_i }

      it "returns arguments unchanged" do
        job = described_class.new(subscriptions, timestamp, invoicing_reason: :subscription_periodic)

        expect(job.lock_key_arguments).to eq(
          [[], timestamp, {invoicing_reason: :subscription_periodic}]
        )
      end
    end

    it "normalizes the timestamp to the date in customer timezone" do
      timestamp = Time.zone.parse("2024-01-15 10:00:00 UTC").to_i

      job = described_class.new(subscriptions, timestamp, invoicing_reason: :subscription_periodic)

      expected_date = Time.zone.parse("2024-01-15T11:00:00+01:00").to_date
      expect(job.lock_key_arguments).to eq(
        [subscriptions, expected_date, {invoicing_reason: :subscription_periodic}]
      )
    end

    it "returns the same lock key for different timestamps on the same day in customer timezone" do
      first_billing_batch_timestamp = Time.zone.parse("2024-01-15 23:00:00 UTC").to_i
      second_billing_batch_timestamp = Time.zone.parse("2024-01-16 00:00:00 UTC").to_i

      morning_job = described_class.new(subscriptions, first_billing_batch_timestamp, invoicing_reason: :subscription_periodic)
      evening_job = described_class.new(subscriptions, second_billing_batch_timestamp, invoicing_reason: :subscription_periodic)
      expect(morning_job.lock_key_arguments).to eq(evening_job.lock_key_arguments)
    end

    it "returns different lock keys for timestamps on different days in customer timezone" do
      first_day_batch_timestamp = Time.zone.parse("2024-01-15 00:00:00 UTC").to_i
      second_day_batch_timestamp = Time.zone.parse("2024-01-15 23:00:00 UTC").to_i

      late_night_job = described_class.new(subscriptions, first_day_batch_timestamp, invoicing_reason: :subscription_periodic)
      after_midnight_job = described_class.new(subscriptions, second_day_batch_timestamp, invoicing_reason: :subscription_periodic)
      expect(late_night_job.lock_key_arguments).not_to eq(after_midnight_job.lock_key_arguments)
    end

    it "returns different lock keys for different subscriptions" do
      timestamp = Time.zone.parse("2024-01-15 10:00:00 UTC").to_i
      other_subscription = create(:subscription, customer:)

      job1 = described_class.new([subscription], timestamp, invoicing_reason: :subscription_periodic)
      job2 = described_class.new([other_subscription], timestamp, invoicing_reason: :subscription_periodic)

      expect(job1.lock_key_arguments).not_to eq(job2.lock_key_arguments)
    end

    it "returns different lock keys for different invoicing reasons" do
      timestamp = Time.zone.parse("2024-01-15 10:00:00 UTC").to_i

      job1 = described_class.new(subscriptions, timestamp, invoicing_reason: :subscription_periodic)
      job2 = described_class.new(subscriptions, timestamp, invoicing_reason: :subscription_starting)

      expect(job1.lock_key_arguments).not_to eq(job2.lock_key_arguments)
    end
  end

  describe "retry_on" do
    [
      [BaseLockService::FailedToAcquireLock.new("customer-1-prepaid_credit"), 25],
      [ActiveRecord::StaleObjectError.new("Attempted to update a stale object: Wallet."), 25],
      [Sequenced::SequenceError.new("Sequenced::SequenceError"), 15]
    ].each do |error, attempts|
      error_class = error.class

      context "when a #{error_class} error is raised" do
        before do
          allow(Invoices::SubscriptionService).to receive(:call).and_raise(error)
        end

        it "raises a #{error_class.name} error and retries" do
          assert_performed_jobs(attempts, only: [described_class]) do
            expect do
              described_class.perform_later(subscriptions, timestamp, invoicing_reason:)
            end.to raise_error(error_class)
          end
        end
      end
    end
  end
end
