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

  describe "happy path: payment succeeds" do
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
  end

  describe "backdated subscription: rules ignored" do
    it "activates immediately without evaluating rules" do
      params = subscription_params.merge(subscription_at: 5.days.ago.iso8601)

      create_subscription(params)

      subscription = customer.subscriptions.sole
      expect(subscription).to be_active
      expect(subscription.activation_rules.count).to eq(0)
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

  describe "manual operations blocked on incomplete" do
    it "rejects terminate and update on incomplete subscriptions" do
      create_subscription(subscription_params)
      perform_all_enqueued_jobs

      subscription = customer.subscriptions.sole
      expect(subscription).to be_incomplete

      terminate_result = Subscriptions::TerminateService.call(subscription:)
      expect(terminate_result).not_to be_success
      expect(terminate_result.error.code).to eq("subscription_incomplete")

      update_result = Subscriptions::UpdateService.call(subscription:, params: {name: "new name"})
      expect(update_result).not_to be_success
      expect(update_result.error.code).to eq("subscription_incomplete")

      expect(subscription.reload).to be_incomplete
    end
  end

  describe "gated subscription with pending VIES check" do
    it "completes the flow: gated → VIES pending → VIES resolved → payment → activation" do
      pending "requires CreateService integration with ActivateService gated path (PR #5370)"

      # 1. Create subscription with payment gating + customer has pending VIES check
      # 2. Invoice created as open, tax_status: pending (VIES blocks tax calculation)
      # 3. No payment triggered yet (can't pay without taxes)
      # 4. VIES resolves → ViesCheckJob picks up the open invoice
      # 5. FinalizePendingViesInvoiceService applies taxes, triggers payment only
      # 6. Payment succeeds → subscription activates, invoice finalized
      raise "not implemented"
    end
  end

  describe "gated subscription with provider tax failure" do
    it "completes the flow: gated → tax failure → retry → payment → activation" do
      pending "requires CreateService integration with ActivateService gated path (PR #5370)"

      # 1. Create subscription with payment gating + customer has tax provider
      # 2. Invoice created as open, tax provider fails → invoice status: failed
      # 3. User retries → RetryService sets status back to open (not pending)
      # 4. PullTaxesAndApplyService succeeds → triggers payment only
      # 5. Payment succeeds → subscription activates, invoice finalized
      raise "not implemented"
  end
end
