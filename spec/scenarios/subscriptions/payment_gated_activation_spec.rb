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

  describe "plan upgrade with payment successful" do
    let(:previous_plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: false, amount_cents: 500)
    end
    let(:upgrade_external_id) { "upgrade-sub-#{SecureRandom.hex(4)}" }

    it "gates the upgrade, then terminates previous and activates new on payment success" do
      # Stage 1: Create initial active subscription on cheaper pay-in-arrears plan (no rules)
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: upgrade_external_id,
        plan_code: previous_plan.code,
        billing_time: "calendar"
      })
      perform_all_enqueued_jobs

      previous_subscription = customer.subscriptions.sole
      expect(previous_subscription).to be_active
      expect(previous_subscription.plan).to eq(previous_plan)

      # Stage 2: Upgrade to pricier pay-in-advance plan with payment activation rule
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: upgrade_external_id,
        plan_code: plan.code,
        billing_time: "calendar",
        activation_rules: [{type: "payment", timeout_hours: 48}]
      })
      perform_all_enqueued_jobs

      new_subscription = customer.subscriptions.where.not(id: previous_subscription.id).sole
      expect(previous_subscription.reload).to be_active
      expect(new_subscription).to be_incomplete
      expect(new_subscription.previous_subscription).to eq(previous_subscription)
      expect(new_subscription.activation_rules.sole).to be_pending

      invoice = new_subscription.invoices.sole
      expect(invoice).to be_open
      expect(invoice.fees.subscription.count).to eq(1)

      # Stage 3: Stripe webhook — payment succeeded → upgrade completes
      expect { simulate_stripe_webhook(status: "succeeded") }
        .to have_performed_job(BillSubscriptionJob)
        .with([previous_subscription], anything, invoicing_reason: :upgrading)

      previous_subscription.reload
      new_subscription.reload
      expect(previous_subscription).to be_terminated
      expect(new_subscription).to be_active
      expect(new_subscription.activated_at).to be_present
      expect(new_subscription.activation_rules.sole).to be_satisfied
      expect(invoice.reload).to be_finalized
    end
  end

  describe "plan upgrade with payment failure" do
    let(:previous_plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: false, amount_cents: 500)
    end
    let(:upgrade_external_id) { "upgrade-sub-#{SecureRandom.hex(4)}" }

    it "cancels the new subscription and leaves the previous untouched" do
      # Stage 1: initial active subscription on cheaper plan
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: upgrade_external_id,
        plan_code: previous_plan.code,
        billing_time: "calendar"
      })
      perform_all_enqueued_jobs

      previous_subscription = customer.subscriptions.sole
      expect(previous_subscription).to be_active

      # Stage 2: gated upgrade
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: upgrade_external_id,
        plan_code: plan.code,
        billing_time: "calendar",
        activation_rules: [{type: "payment", timeout_hours: 48}]
      })
      perform_all_enqueued_jobs

      new_subscription = customer.subscriptions.where.not(id: previous_subscription.id).sole
      expect(new_subscription).to be_incomplete

      invoice = new_subscription.invoices.sole
      expect(invoice).to be_open

      # Stage 3: Stripe webhook — payment failed
      simulate_stripe_webhook(status: "failed")

      previous_subscription.reload
      new_subscription.reload
      expect(new_subscription).to be_canceled
      expect(new_subscription.cancelation_reason).to eq("payment_failed")
      expect(new_subscription.activation_rules.sole).to be_failed
      expect(previous_subscription).to be_active
      expect(invoice.reload).to be_closed
    end
  end

  describe "plan downgrade with payment successful", transaction: false do
    let(:previous_plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: false, amount_cents: 2000)
    end
    let(:downgrade_external_id) { "downgrade-sub-#{SecureRandom.hex(4)}" }

    # This scenario spans a real billing period, so terminating the previous subscription on
    # activation produces a non-zero invoice and thus a second payment intent.
    # The shared stub returns a fixed payment_intent_id, which would collide
    # with the gated invoice's payment on the second call — return a unique id per call, as Stripe
    # does.
    before do
      allow_any_instance_of(::PaymentProviders::Stripe::Payments::CreateService) # rubocop:disable RSpec/AnyInstance
        .to receive(:create_payment_intent) do
          Stripe::PaymentIntent.construct_from(
            id: "pi_#{SecureRandom.hex(12)}",
            status: "processing",
            amount: 1000,
            currency: "eur"
          )
        end
    end

    it "gates the downgrade at the billing boundary, then terminates previous and activates new on payment success" do
      # Stage 1: active subscription on the pricier plan (no rules)
      travel_to(DateTime.new(2024, 1, 10)) do
        create_subscription({
          external_customer_id: customer.external_id,
          external_id: downgrade_external_id,
          plan_code: previous_plan.code,
          billing_time: "calendar"
        })
        perform_all_enqueued_jobs
      end

      previous_subscription = customer.subscriptions.sole
      expect(previous_subscription).to be_active
      expect(previous_subscription.plan).to eq(previous_plan)

      # Stage 2: downgrade to the cheaper pay-in-advance plan with a payment activation rule.
      # The downgrade is created pending and only activated at the next billing day.
      travel_to(DateTime.new(2024, 1, 20)) do
        create_subscription({
          external_customer_id: customer.external_id,
          external_id: downgrade_external_id,
          plan_code: plan.code,
          billing_time: "calendar",
          activation_rules: [{type: "payment", timeout_hours: 48}]
        })
        perform_all_enqueued_jobs
      end

      new_subscription = customer.subscriptions.where.not(id: previous_subscription.id).sole
      expect(new_subscription).to be_pending
      expect(new_subscription.previous_subscription).to eq(previous_subscription)
      expect(previous_subscription.reload).to be_active

      # Stage 3: next billing day — the rotation gates the pending downgrade rather than activating it.
      travel_to(DateTime.new(2024, 2, 1)) do
        perform_billing
      end

      new_subscription.reload
      expect(new_subscription).to be_incomplete
      expect(new_subscription.activation_rules.sole).to be_pending
      expect(previous_subscription.reload).to be_active

      invoice = new_subscription.invoices.sole
      expect(invoice).to be_open
      expect(invoice.fees.subscription.count).to eq(1)

      # Stage 4: Stripe webhook — payment succeeded → previous terminates, downgrade activates
      travel_to(DateTime.new(2024, 2, 1)) do
        expect { simulate_stripe_webhook(status: "succeeded") }
          .to have_performed_job(BillSubscriptionJob)
          .with([previous_subscription], anything, invoicing_reason: :upgrading)
      end

      previous_subscription.reload
      new_subscription.reload
      expect(previous_subscription).to be_terminated
      expect(new_subscription).to be_active
      expect(new_subscription.activated_at).to be_present
      expect(new_subscription.activation_rules.sole).to be_satisfied
      expect(invoice.reload).to be_finalized
    end
  end

  describe "plan downgrade with payment failure", transaction: false do
    let(:previous_plan) do
      create(:plan, organization:, interval: "monthly", pay_in_advance: false, amount_cents: 2000)
    end
    let(:downgrade_external_id) { "downgrade-sub-#{SecureRandom.hex(4)}" }

    it "cancels the new subscription and leaves the previous untouched" do
      # Stage 1: active subscription on the pricier plan
      travel_to(DateTime.new(2024, 1, 10)) do
        create_subscription({
          external_customer_id: customer.external_id,
          external_id: downgrade_external_id,
          plan_code: previous_plan.code,
          billing_time: "calendar"
        })
        perform_all_enqueued_jobs
      end

      previous_subscription = customer.subscriptions.sole
      expect(previous_subscription).to be_active

      # Stage 2: gated downgrade (pending until next billing day)
      travel_to(DateTime.new(2024, 1, 20)) do
        create_subscription({
          external_customer_id: customer.external_id,
          external_id: downgrade_external_id,
          plan_code: plan.code,
          billing_time: "calendar",
          activation_rules: [{type: "payment", timeout_hours: 48}]
        })
        perform_all_enqueued_jobs
      end

      new_subscription = customer.subscriptions.where.not(id: previous_subscription.id).sole
      expect(new_subscription).to be_pending

      # Stage 3: next billing day — rotation gates the downgrade
      travel_to(DateTime.new(2024, 2, 1)) do
        perform_billing
      end

      new_subscription.reload
      expect(new_subscription).to be_incomplete

      invoice = new_subscription.invoices.sole
      expect(invoice).to be_open

      # Stage 4: Stripe webhook — payment failed
      travel_to(DateTime.new(2024, 2, 1)) do
        simulate_stripe_webhook(status: "failed")
      end

      previous_subscription.reload
      new_subscription.reload
      expect(new_subscription).to be_canceled
      expect(new_subscription.cancelation_reason).to eq("payment_failed")
      expect(new_subscription.activation_rules.sole).to be_failed
      expect(previous_subscription).to be_active
      expect(invoice.reload).to be_closed
    end
  end
end
