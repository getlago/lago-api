# frozen_string_literal: true

require "rails_helper"

describe "Dunning Campaign v1", :scenarios, type: :request do
  let(:webhook_url) { "https://test.co/lago" }
  let(:organization) do
    create(:organization,
      name: "JC AI",
      premium_integrations: %w[auto_dunning],
      email_settings: [],
      webhook_url:)
  end

  let(:dunning_campaign) do
    create(:dunning_campaign, organization:,
      applied_to_organization: true, max_attempts: 2, days_between_attempts: 2)
  end
  let(:dunning_campaign_threshold) do
    create(:dunning_campaign_threshold, dunning_campaign:, amount_cents: 150_00, currency: "EUR")
  end
  let(:stripe_cus_id) { "cus_123456789" }
  let(:stripe_pm_id) { "pm_123456" }

  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:customer) { create(:customer, organization:, payment_provider: :stripe, payment_provider_code: stripe_provider.code, net_payment_term: 2) }
  let(:stripe_customer) { create(:stripe_customer, customer:, payment_provider: stripe_provider, provider_customer_id: stripe_cus_id) }

  let(:external_subscription_id) { "sub_overdue-dunning-campaign-v1" }
  let(:plan) { create(:plan, organization:, pay_in_advance: true, amount_cents: 149_00) }
  let!(:addon) { create(:add_on, organization:) }

  let(:webhooks_sent) { [] }

  let(:stripe_customer_response) do
    File.read("spec/fixtures/stripe/customer_retrieve_response.json")
  end
  # TODO: this is part of another PR coming soon https://github.com/getlago/lago-api/pull/3345
  let(:stripe_payment_method_response) do
    {
      id: stripe_pm_id,
      object: "payment_method",
      allow_redisplay: "always",
      billing_details: {
        address: {
          city: nil,
          country: "FR",
          line1: nil,
          line2: nil,
          postal_code: nil,
          state: nil
        },
        email: "awdawd@desf.com",
        name: "Testing Stripe",
        phone: nil
      },
      card: {
        brand: "visa",
        checks: {
          address_line1_check: nil,
          address_postal_code_check: nil,
          cvc_check: "pass"
        },
        country: "US",
        display_brand: "visa",
        exp_month: 12,
        exp_year: 2028,
        fingerprint: "8TOiB4cGytYxCweY",
        funding: "credit",
        generated_from: nil,
        last4: "4242",
        networks: {
          available: [
            "visa"
          ],
          preferred: nil
        },
        regulated_status: "unregulated",
        three_d_secure_usage: {
          supported: true
        },
        wallet: nil
      },
      created: 1741878064,
      customer: stripe_cus_id,
      livemode: false,
      metadata: {},
      type: "card"
    }
  end
  let(:stripe_payment_intent_response) do
    File.read("spec/fixtures/stripe/payment_intent_failed_card_declined.json")
  end

  # TODO: make it a test metadata `:scenarios, type: :request, premium: true`
  around { |test| lago_premium!(&test) }

  before do
    stub_pdf_generation
    stripe_customer
    dunning_campaign_threshold

    stub_request(:post, webhook_url).with do |req|
      webhooks_sent << JSON.parse(req.body)
      true
    end.and_return(status: 200)

    stub_request(:get, "https://api.stripe.com/v1/customers/#{stripe_customer.provider_customer_id}")
      .and_return(status: 200, body: stripe_customer_response)
    stub_request(:get, "https://api.stripe.com/v1/customers/#{stripe_customer.provider_customer_id}/payment_methods/pm_123456")
      .and_return(status: 200, body: stripe_payment_method_response.to_json)
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .and_return(status: 402, body: stripe_payment_intent_response)
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .and_return(status: 200, body: {url: "https://stripe.com/checkout/session/cs_test_123"}.to_json)
  end

  it do
    travel_to(DateTime.new(2025, 1, 1, 10)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: external_subscription_id,
          plan_code: plan.code
        }
      )
      perform_billing

      expect(webhooks_sent.map { _1["webhook_type"] }).to eq(%w[
        subscription.started
        invoice.created
        invoice.generated
        invoice.payment_failure
      ])
      invoice = customer.invoices.sole
      expect(invoice.payment_status).to eq("failed")
      expect(invoice.payment_due_date).to eq(Date.new(2025, 1, 3))
    end

    # The day after payment_due_date, the invoice should be marked as overdue
    travel_to(DateTime.new(2025, 1, 4, 13)) do
      perform_overdue_balance_update

      invoice = customer.invoices.sole
      expect(invoice).to be_payment_overdue
      expect(customer.overdue_balance_cents).to eq(149_00)

      # Performing dunning has no effect because the threshold is 150 and we have only 149 overdue
      perform_dunning
      expect(customer.payment_requests.count).to eq(0)
    end

    # Create a one-off invoice to reach the threshold
    travel_to(DateTime.new(2025, 1, 4, 18)) do
      create_one_off_invoice(customer, [addon], units: 3)
      perform_all_enqueued_jobs

      oneoff = customer.invoices.one_off.sole
      expect(oneoff.payment_status).to eq("failed")
      expect(oneoff.payment_due_date).to eq(Date.new(2025, 1, 6))
    end

    travel_to(DateTime.new(2025, 1, 7, 10)) do
      perform_overdue_balance_update
      expect(customer.invoices.one_off.sole).to be_payment_overdue

      expect(ActionMailer::Base.deliveries.count).to eq(0)
      perform_dunning
      expect(ActionMailer::Base.deliveries.count).to eq(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to eq "Your overdue balance from JC AI"

      pr = customer.payment_requests.sole
      expect(pr.amount_cents).to eq(155_00)

      # TODO Simulate webhook payment failed received
    end

    # The next 2 days nothing happens
    [DateTime.new(2025, 1, 8, 10), DateTime.new(2025, 1, 9, 10)].each do |date|
      travel_to(date) do
        perform_overdue_balance_update
        perform_dunning
        expect(ActionMailer::Base.deliveries.count).to eq(1)
      end
    end

    # The next day nothing happens
    travel_to(DateTime.new(2025, 1, 10, 10)) do
      perform_overdue_balance_update
      perform_dunning
      expect(ActionMailer::Base.deliveries.count).to eq(2)

      expect(customer.payment_requests.reload.map(&:amount_cents)).to eq([155_00, 155_00])
    end

    # This is over
    travel_to(DateTime.new(2025, 1, 13, 13)) do
      perform_overdue_balance_update
      perform_dunning
      expect(ActionMailer::Base.deliveries.count).to eq(2)
    end
  end
end
