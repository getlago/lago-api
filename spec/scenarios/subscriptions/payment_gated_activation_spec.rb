# frozen_string_literal: true

require "rails_helper"

describe "Payment Gated Subscription Activation Scenarios" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:stripe_customer) { create(:stripe_customer, payment_provider: stripe_provider, customer:) }
  let(:payment_method) { create(:payment_method, customer:) }
  let(:payment_intent_id) { "pi_#{SecureRandom.hex(12)}" }

  let(:plan) do
    create(:plan, organization:, interval: "monthly", pay_in_advance: true, amount_cents: 1000)
  end

  let(:subscription_params) do
    {
      external_customer_id: customer.external_id,
      external_id: "gated-sub-#{SecureRandom.hex(4)}",
      plan_code: plan.code,
      billing_time: "calendar",
      activation_rules: [{type: "payment", timeout_hours: 48}]
    }
  end

  before do
    create(:tax, :applied_to_billing_entity, organization:, rate: 0)
    customer.update!(payment_provider: :stripe, payment_provider_code: stripe_provider.code)
    stripe_customer
    payment_method

    # Stub Stripe to return processing — payment stays pending, subscription remains incomplete
    allow_any_instance_of(::PaymentProviders::Stripe::Payments::CreateService) # rubocop:disable RSpec/AnyInstance
      .to receive(:create_payment_intent)
      .and_return(
        Stripe::PaymentIntent.construct_from(
          id: payment_intent_id,
          status: "processing",
          amount: 1000,
          currency: "eur"
        )
      )
  end

  def simulate_stripe_webhook(status:)
    payment = Payment.order(created_at: :desc).first
    payment.update!(provider_payment_id: payment_intent_id)

    # Stub payment method retrieval triggered by SetPaymentMethodAndCreateReceiptJob
    stub_request(:get, %r{https://api.stripe.com/v1/payment_methods/.*})
      .and_return(status: 200, body: {id: "pm_test", object: "payment_method", type: "card"}.to_json)

    event_type = (status == "succeeded") ? "payment_intent.succeeded" : "payment_intent.payment_failed"

    PaymentProviders::Stripe::HandleEventService.call!(
      organization:,
      event_json: {
        id: "evt_#{SecureRandom.hex(10)}",
        object: "event",
        type: event_type,
        data: {
          object: {
            id: payment_intent_id,
            object: "payment_intent",
            status: status.to_s,
            payment_method: "pm_test",
            metadata: {
              lago_invoice_id: payment.payable_id,
              lago_customer_id: customer.id
            }
          }
        }
      }.to_json
    )
    perform_all_enqueued_jobs
  end

  describe "new subscription with payment successful" do
    it "creates incomplete subscription, then activates on payment success" do
      # Stage 1: Create subscription — goes incomplete, invoice open
      create_subscription(subscription_params)
      perform_all_enqueued_jobs

      subscription = customer.subscriptions.sole
      expect(subscription).to be_incomplete
      expect(subscription.started_at).to be_present
      expect(subscription.activated_at).to be_nil
      expect(subscription.activation_rules.sole).to be_pending

      invoice = subscription.invoices.sole
      expect(invoice).to be_open
      expect(invoice.fees.subscription.count).to eq(1)

      # Stage 2: Stripe webhook — payment succeeded
      simulate_stripe_webhook(status: "succeeded")

      subscription.reload
      expect(subscription).to be_active
      expect(subscription.activated_at).to be_present
      expect(subscription.activation_rules.sole).to be_satisfied

      expect(invoice.reload).to be_finalized
      expect(invoice.number).not_to include("DRAFT")
    end
  end

  describe "payment failure: subscription canceled" do
    it "creates incomplete subscription, then cancels on payment failure" do
      # Stage 1: Create subscription — goes incomplete
      create_subscription(subscription_params)
      perform_all_enqueued_jobs

      subscription = customer.subscriptions.sole
      expect(subscription).to be_incomplete

      invoice = subscription.invoices.sole
      expect(invoice).to be_open

      # Stage 2: Stripe webhook — payment failed
      simulate_stripe_webhook(status: "failed")

      subscription.reload
      expect(subscription).to be_canceled
      expect(subscription.cancelation_reason).to eq("payment_failed")
      expect(subscription.activated_at).to be_nil
      expect(subscription.activation_rules.sole).to be_failed

      expect(invoice.reload).to be_closed
    end

    context "with consumed coupon, credit note, and wallet credits" do
      let(:coupon) do
        create(:coupon, organization:, coupon_type: :fixed_amount,
          amount_cents: 10, amount_currency: "EUR", frequency: :once)
      end
      let(:applied_coupon) do
        create(:applied_coupon, customer:, coupon:, organization:,
          amount_cents: 10, amount_currency: "EUR", frequency: :once, status: :active)
      end
      let(:source_invoice) do
        create(:invoice, customer:, organization:, status: :finalized, currency: "EUR")
      end
      let(:credit_note) do
        create(:credit_note, customer:, organization:, invoice: source_invoice,
          credit_status: :available,
          total_amount_cents: 10, total_amount_currency: "EUR",
          credit_amount_cents: 10, credit_amount_currency: "EUR",
          balance_amount_cents: 10, balance_amount_currency: "EUR")
      end
      let(:wallet) do
        create(:wallet, :with_inbound_transaction, customer:, organization:, currency: "EUR",
          balance_cents: 10, credits_balance: 0.1, rate_amount: 1)
      end

      before do
        applied_coupon
        credit_note
        wallet
      end

      it "restores the coupon, credit note balance, and wallet credits when payment fails" do
        create_subscription(subscription_params)
        perform_all_enqueued_jobs

        invoice = customer.subscriptions.sole.invoices.sole
        expect(invoice).to be_open

        # Resources consumed by the gated invoice
        expect(applied_coupon.reload).to be_terminated
        expect(credit_note.reload.balance_amount_cents).to eq(0)
        expect(credit_note).to be_consumed
        expect(wallet.reload.balance_cents).to eq(0)

        simulate_stripe_webhook(status: "failed")

        expect(invoice.reload).to be_closed

        # Resources restored after the gated invoice was closed
        expect(applied_coupon.reload).to be_active
        expect(applied_coupon.remaining_amount).to eq(10)
        expect(credit_note.reload.balance_amount_cents).to eq(10)
        expect(credit_note).to be_available
        expect(wallet.reload.balance_cents).to eq(10)
        expect(wallet.wallet_transactions.inbound.where(voided_invoice_id: invoice.id)).to exist
      end

      context "when the credit note is voided" do
        let(:credit_note) do
          create(:credit_note, customer:, organization:, invoice: source_invoice,
            credit_status: :voided,
            total_amount_cents: 10, total_amount_currency: "EUR",
            credit_amount_cents: 10, credit_amount_currency: "EUR",
            balance_amount_cents: 10, balance_amount_currency: "EUR")
        end

        it "leaves the voided credit note untouched when payment fails" do
          create_subscription(subscription_params)
          perform_all_enqueued_jobs

          simulate_stripe_webhook(status: "failed")

          expect(invoice.reload).to be_closed
          expect(credit_note.reload).to be_voided
          expect(credit_note.balance_amount_cents).to eq(10)
        end
      end

      context "when the wallet is terminated" do
        let(:wallet) do
          create(:wallet, :terminated, customer:, organization:, currency: "EUR",
            balance_cents: 10, credits_balance: 0.1, rate_amount: 1)
        end

        it "leaves the terminated wallet untouched when payment fails" do
          create_subscription(subscription_params)
          perform_all_enqueued_jobs

          simulate_stripe_webhook(status: "failed")

          expect(invoice.reload).to be_closed
          expect(wallet.reload).to be_terminated
          expect(wallet.balance_cents).to eq(10)
          expect(wallet.wallet_transactions.inbound.where(voided_invoice_id: invoice.id)).not_to exist
        end
      end
    end
  end

  describe "backdated subscription: rules ignored" do
    it "activates immediately without evaluating rules" do
      params = subscription_params.merge(subscription_at: 5.days.ago.iso8601)

      create_subscription(params)

      subscription = customer.subscriptions.sole
      expect(subscription).to be_active
      expect(subscription.activation_rules.count).to eq(0)
      expect(subscription.invoices).to be_empty
    end
  end

  describe "with trial period" do
    let(:plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: true, amount_cents: 1000, trial_period: 30)
    end

    context "when plan has no pay-in-advance fixed charges" do
      it "activates immediately because there is nothing to collect" do
        create_subscription(subscription_params)
        perform_all_enqueued_jobs

        subscription = customer.subscriptions.sole
        expect(subscription).to be_active
        expect(subscription.activation_rules.sole).to be_not_applicable
        expect(subscription.invoices).to be_empty
      end
    end

    context "when plan has pay-in-advance fixed charges" do
      let(:add_on) { create(:add_on, organization:) }

      before { create(:fixed_charge, plan:, add_on:, pay_in_advance: true) }

      it "gates on the fixed charge invoice" do
        create_subscription(subscription_params)
        perform_all_enqueued_jobs

        subscription = customer.subscriptions.sole
        expect(subscription).to be_incomplete
        expect(subscription.activation_rules.sole).to be_pending
      end
    end
  end

  describe "zero-amount gated invoice (no charge to collect)" do
    let(:plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: true, amount_cents: 0)
    end

    it "marks the rule satisfied and activates without going through the payment chain" do
      create_subscription(subscription_params)
      perform_all_enqueued_jobs

      subscription = customer.subscriptions.sole
      expect(subscription).to be_active
      expect(subscription.activation_rules.sole).to be_satisfied

      invoice = subscription.invoices.sole
      expect(invoice).to be_finalized
      expect(invoice.total_amount_cents).to eq(0)
      expect(invoice.payment_status).to eq("succeeded")
    end
  end

  describe "pay-in-arrears plan with pay-in-advance fixed charges" do
    let(:plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: false, amount_cents: 1000)
    end
    let(:add_on) { create(:add_on, organization:) }

    before { create(:fixed_charge, plan:, add_on:, pay_in_advance: true) }

    it "gates on the fixed charge only invoice" do
      create_subscription(subscription_params)
      perform_all_enqueued_jobs

      subscription = customer.subscriptions.sole
      expect(subscription).to be_incomplete
      expect(subscription.activation_rules.sole).to be_pending

      invoice = subscription.invoices.sole
      expect(invoice).to be_open
      expect(invoice.fees.fixed_charge.count).to be_positive
      expect(invoice.fees.subscription.count).to eq(0)
    end
  end

  describe "timeout: subscription cancels on activation rule expiry" do
    before do
      # Best-effort PSP cancel calls Stripe; mock the SDK to return a canceled intent.
      allow(::Stripe::PaymentIntent).to receive(:cancel).and_return(
        ::Stripe::PaymentIntent.construct_from(
          id: payment_intent_id,
          object: "payment_intent",
          status: "canceled",
          amount: 1000,
          currency: "eur"
        )
      )
    end

    it "expires the gated subscription with cancelation_reason: timeout" do
      # Stage 1: Create gated subscription
      create_subscription(subscription_params)
      perform_all_enqueued_jobs

      subscription = customer.subscriptions.sole
      expect(subscription).to be_incomplete
      expect(subscription.activation_rules.sole).to be_pending

      invoice = subscription.invoices.sole
      expect(invoice).to be_open

      # Stage 2: Simulate timeout — push the rule's expires_at into the past
      subscription.activation_rules.sole.update!(expires_at: 1.hour.ago)

      # Stage 3: Clock job runs — picks up the expired rule, enqueues ExpireIncompleteJob
      Clock::ExpireIncompleteSubscriptionsJob.perform_now
      perform_all_enqueued_jobs

      subscription.reload
      expect(subscription).to be_canceled
      expect(subscription.cancelation_reason).to eq("timeout")
      expect(subscription.activation_rules.sole).to be_expired

      expect(invoice.reload).to be_closed
    end

    it "does not act on subscriptions whose rule has not yet expired" do
      create_subscription(subscription_params)
      perform_all_enqueued_jobs

      subscription = customer.subscriptions.sole
      expect(subscription).to be_incomplete

      # Rule's expires_at is still in the future (48 hours from creation)
      Clock::ExpireIncompleteSubscriptionsJob.perform_now
      perform_all_enqueued_jobs

      expect(subscription.reload).to be_incomplete
      expect(subscription.activation_rules.sole).to be_pending
    end

    context "with consumed coupon, credit note, and wallet credits" do
      let(:coupon) do
        create(:coupon, organization:, coupon_type: :fixed_amount,
          amount_cents: 10, amount_currency: "EUR", frequency: :once)
      end
      let(:applied_coupon) do
        create(:applied_coupon, customer:, coupon:, organization:,
          amount_cents: 10, amount_currency: "EUR", frequency: :once, status: :active)
      end
      let(:source_invoice) do
        create(:invoice, customer:, organization:, status: :finalized, currency: "EUR")
      end
      let(:credit_note) do
        create(:credit_note, customer:, organization:, invoice: source_invoice,
          credit_status: :available,
          total_amount_cents: 10, total_amount_currency: "EUR",
          credit_amount_cents: 10, credit_amount_currency: "EUR",
          balance_amount_cents: 10, balance_amount_currency: "EUR")
      end
      let(:wallet) do
        create(:wallet, :with_inbound_transaction, customer:, organization:, currency: "EUR",
          balance_cents: 10, credits_balance: 0.1, rate_amount: 1)
      end

      before do
        applied_coupon
        credit_note
        wallet
      end

      it "restores the coupon, credit note balance, and wallet credits when the rule expires" do
        create_subscription(subscription_params)
        perform_all_enqueued_jobs

        invoice = customer.subscriptions.sole.invoices.sole
        expect(invoice).to be_open

        # Resources consumed by the gated invoice
        expect(applied_coupon.reload).to be_terminated
        expect(credit_note.reload.balance_amount_cents).to eq(0)
        expect(credit_note).to be_consumed
        expect(wallet.reload.balance_cents).to eq(0)

        # Push the rule's expires_at into the past and run the clock
        customer.subscriptions.sole.activation_rules.sole.update!(expires_at: 1.hour.ago)
        Clock::ExpireIncompleteSubscriptionsJob.perform_now
        perform_all_enqueued_jobs

        expect(invoice.reload).to be_closed

        # Resources restored after the gated invoice was closed
        expect(applied_coupon.reload).to be_active
        expect(applied_coupon.remaining_amount).to eq(10)
        expect(credit_note.reload.balance_amount_cents).to eq(10)
        expect(credit_note).to be_available
        expect(wallet.reload.balance_cents).to eq(10)
        expect(wallet.wallet_transactions.inbound.where(voided_invoice_id: invoice.id)).to exist
      end

      context "when the credit note is voided" do
        let(:credit_note) do
          create(:credit_note, customer:, organization:, invoice: source_invoice,
            credit_status: :voided,
            total_amount_cents: 10, total_amount_currency: "EUR",
            credit_amount_cents: 10, credit_amount_currency: "EUR",
            balance_amount_cents: 10, balance_amount_currency: "EUR")
        end

        it "leaves the voided credit note untouched when the rule expires" do
          create_subscription(subscription_params)
          perform_all_enqueued_jobs

          invoice = customer.subscriptions.sole.invoices.sole
          expect(invoice.credits.credit_note_kind).to be_empty

          customer.subscriptions.sole.activation_rules.sole.update!(expires_at: 1.hour.ago)
          Clock::ExpireIncompleteSubscriptionsJob.perform_now
          perform_all_enqueued_jobs

          expect(invoice.reload).to be_closed
          expect(credit_note.reload).to be_voided
          expect(credit_note.balance_amount_cents).to eq(10)
        end
      end

      context "when the wallet is terminated" do
        let(:wallet) do
          create(:wallet, :terminated, customer:, organization:, currency: "EUR",
            balance_cents: 10, credits_balance: 0.1, rate_amount: 1)
        end

        it "leaves the terminated wallet untouched when the rule expires" do
          create_subscription(subscription_params)
          perform_all_enqueued_jobs

          invoice = customer.subscriptions.sole.invoices.sole
          expect(invoice.wallet_transactions.outbound).to be_empty

          customer.subscriptions.sole.activation_rules.sole.update!(expires_at: 1.hour.ago)
          Clock::ExpireIncompleteSubscriptionsJob.perform_now
          perform_all_enqueued_jobs

          expect(invoice.reload).to be_closed
          expect(wallet.reload).to be_terminated
          expect(wallet.balance_cents).to eq(10)
          expect(wallet.wallet_transactions.inbound.where(voided_invoice_id: invoice.id)).not_to exist
        end
      end
    end
  end

  describe "gated subscription with pending VIES check" do
    let(:vat_number) { "IT12345678901" }
    let(:organization) do
      create(:organization, country: "FR", webhook_url: nil, eu_tax_management: true,
        billing_entities: [create(:billing_entity, country: "FR", eu_tax_management: true)])
    end
    let(:billing_entity) { organization.billing_entities.first }
    let(:customer) do
      create(:customer, organization:, billing_entity:, country: "IT", currency: "EUR",
        tax_identification_number: vat_number)
    end

    before do
      create(:pending_vies_check, customer:, tax_identification_number: vat_number)
    end

    it "stays gated until VIES resolves, then activates on payment success" do
      # Stage 1: Create subscription — invoice goes :open with tax_status :pending (VIES blocks taxes)
      create_subscription(subscription_params)
      perform_all_enqueued_jobs

      subscription = customer.subscriptions.sole
      expect(subscription).to be_incomplete
      expect(subscription.activation_rules.sole).to be_pending

      invoice = subscription.invoices.sole
      expect(invoice).to be_open
      expect(invoice.tax_status).to eq("pending")

      # Stage 2: VIES resolves — FinalizePendingViesInvoiceService applies taxes and triggers payment
      mock_vies_check!(vat_number)
      Customers::ViesCheckJob.perform_now(customer)
      perform_all_enqueued_jobs

      invoice.reload
      expect(invoice.tax_status).to eq("succeeded")
      expect(invoice).to be_open

      # Stage 3: Stripe webhook — payment succeeded, subscription activates
      simulate_stripe_webhook(status: "succeeded")

      subscription.reload
      expect(subscription).to be_active
      expect(subscription.activation_rules.sole).to be_satisfied
      expect(invoice.reload).to be_finalized
    end
  end

  describe "gated subscription with provider tax failure" do
    let(:tax_integration) { create(:anrok_integration, organization:) }
    let(:tax_integration_customer) { create(:anrok_customer, integration: tax_integration, customer:) }
    let(:anrok_client) { instance_double(LagoHttpClient::Client) }
    let(:anrok_finalized_endpoint) { "https://api.nango.dev/v1/anrok/finalized_invoices" }
    let(:anrok_draft_endpoint) { "https://api.nango.dev/v1/anrok/draft_invoices" }
    let(:failure_body) { File.read(Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json")) }
    let(:success_body_template) { JSON.parse(File.read(Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response.json"))) }

    before do
      tax_integration_customer
      allow(LagoHttpClient::Client).to receive(:new).and_call_original
      allow(LagoHttpClient::Client).to receive(:new).with(anrok_finalized_endpoint, anything).and_return(anrok_client)
      allow(LagoHttpClient::Client).to receive(:new).with(anrok_draft_endpoint, anything).and_return(anrok_client)
      stub_anrok_response(failure_body)
    end

    def stub_anrok_response(body)
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:body).and_return(body)
      allow(anrok_client).to receive(:post_with_response).and_return(response)
    end

    def success_body_for(invoice)
      body = success_body_template.deep_dup
      body["succeededInvoices"].first["fees"].first["item_id"] = invoice.fees.first.id
      body.to_json
    end

    it "fails on tax error, retries successfully, then activates on payment success" do
      # Stage 1: Create subscription — Anrok fails → invoice :failed
      create_subscription(subscription_params)
      perform_all_enqueued_jobs

      subscription = customer.subscriptions.sole
      expect(subscription).to be_incomplete
      expect(subscription.activation_rules.sole).to be_pending

      invoice = subscription.invoices.sole
      expect(invoice).to be_failed
      expect(invoice.tax_status).to eq("failed")

      # Stage 2: Re-stub Anrok to succeed, then retry. Invoice goes :open with taxes
      # applied; PullTaxesAndApplyService triggers payment for the gated case.
      stub_anrok_response(success_body_for(invoice))
      Invoices::RetryService.call!(invoice:)
      perform_all_enqueued_jobs

      invoice.reload
      expect(invoice).to be_open
      expect(invoice.tax_status).to eq("succeeded")

      # Stage 3: Stripe webhook — payment succeeded, subscription activates
      simulate_stripe_webhook(status: "succeeded")

      subscription.reload
      expect(subscription).to be_active
      expect(subscription.activation_rules.sole).to be_satisfied
      expect(invoice.reload).to be_finalized
    end
  end
end
