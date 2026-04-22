# frozen_string_literal: true

require "rails_helper"

describe "Payment Gated Subscription Activation Scenarios" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, payment_provider: "stripe") }
  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:stripe_customer) { create(:stripe_customer, payment_provider: stripe_provider, customer:) }
  let(:payment_method) { create(:payment_method, customer:) }

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
    stripe_provider
    stripe_customer
    payment_method
  end

  describe "happy path: payment succeeds" do
    it "creates incomplete subscription, then activates on payment success" do
      # Step 1: Create subscription with payment gating
      create_subscription(subscription_params)
      perform_enqueued_jobs

      subscription = customer.subscriptions.sole
      expect(subscription).to be_incomplete
      expect(subscription.started_at).to be_present
      expect(subscription.activated_at).to be_nil

      # Verify activation rule
      rule = subscription.activation_rules.sole
      expect(rule).to be_pending
      expect(rule.type).to eq("payment")
      expect(rule.expires_at).to be_present

      # Verify invoice created as open
      invoice = subscription.invoices.sole
      expect(invoice).to be_open
      expect(invoice.fees.subscription.count).to eq(1)
      expect(invoice.total_amount_cents).to be_positive

      # Verify webhooks
      expect(SendWebhookJob).to have_been_enqueued.with("subscription.incomplete", subscription)

      # Step 2: Simulate payment success (PSP webhook)
      Invoices::UpdateService.call!(
        invoice:,
        params: {payment_status: "succeeded"},
        webhook_notification: false
      )
      perform_enqueued_jobs

      # Verify subscription activated
      subscription.reload
      expect(subscription).to be_active
      expect(subscription.activated_at).to be_present

      # Verify rule resolved
      expect(rule.reload).to be_satisfied

      # Verify invoice finalized
      invoice.reload
      expect(invoice).to be_finalized
      expect(invoice.number).not_to include("DRAFT")

      # Verify webhooks
      expect(SendWebhookJob).to have_been_enqueued.with("subscription.started", subscription)
    end
  end

  describe "payment failure: subscription canceled" do
    it "creates incomplete subscription, then cancels on payment failure" do
      # Step 1: Create subscription with payment gating
      create_subscription(subscription_params)
      perform_enqueued_jobs

      subscription = customer.subscriptions.sole
      expect(subscription).to be_incomplete

      invoice = subscription.invoices.sole
      expect(invoice).to be_open

      # Step 2: Simulate payment failure (PSP webhook)
      Invoices::UpdateService.call!(
        invoice:,
        params: {payment_status: "failed"},
        webhook_notification: false
      )
      perform_enqueued_jobs

      # Verify subscription canceled
      subscription.reload
      expect(subscription).to be_canceled
      expect(subscription.cancelation_reason).to eq("payment_failed")
      expect(subscription.activated_at).to be_nil

      # Verify rule resolved
      rule = subscription.activation_rules.sole
      expect(rule).to be_failed

      # Verify invoice closed
      expect(invoice.reload).to be_closed

      # Verify webhooks
      expect(SendWebhookJob).to have_been_enqueued.with("subscription.canceled", subscription)
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
        perform_enqueued_jobs

        subscription = customer.subscriptions.sole
        expect(subscription).to be_active

        rule = subscription.activation_rules.sole
        expect(rule).to be_not_applicable
      end
    end

    context "when plan has pay-in-advance fixed charges" do
      let(:add_on) { create(:add_on, organization:) }

      before { create(:fixed_charge, plan:, add_on:, pay_in_advance: true) }

      it "gates on the fixed charge invoice" do
        create_subscription(subscription_params)
        perform_enqueued_jobs

        subscription = customer.subscriptions.sole
        expect(subscription).to be_incomplete

        rule = subscription.activation_rules.sole
        expect(rule).to be_pending
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
      perform_enqueued_jobs

      subscription = customer.subscriptions.sole
      expect(subscription).to be_incomplete

      rule = subscription.activation_rules.sole
      expect(rule).to be_pending

      # Invoice should contain fixed charge fees only
      invoice = subscription.invoices.sole
      expect(invoice).to be_open
      expect(invoice.fees.fixed_charge.count).to be_positive
      expect(invoice.fees.subscription.count).to eq(0)
    end
  end


  describe "manual operations blocked on incomplete" do
    it "rejects terminate and update on incomplete subscriptions" do
      create_subscription(subscription_params)
      perform_enqueued_jobs

      subscription = customer.subscriptions.sole
      expect(subscription).to be_incomplete

      # Terminate should fail
      terminate_result = Subscriptions::TerminateService.call(subscription:)
      expect(terminate_result).not_to be_success
      expect(terminate_result.error.code).to eq("subscription_incomplete")

      # Update should fail
      update_result = Subscriptions::UpdateService.call(subscription:, params: {name: "new name"})
      expect(update_result).not_to be_success
      expect(update_result.error.code).to eq("subscription_incomplete")

      # Subscription unchanged
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
