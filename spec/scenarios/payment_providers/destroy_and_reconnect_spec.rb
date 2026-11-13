# frozen_string_literal: true

require "rails_helper"

describe "Payment Provider Destroy And Reconnect Scenarios" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  before do
    stub_request(:get, %r{/v1/customers/[^/]+$}).and_return(
      status: 200, body: get_stripe_fixtures("customer_retrieve_response.json")
    )
    stub_request(:get, %r{/v1/customers/[^/]+/payment_methods}).and_return(
      status: 200, body: get_stripe_fixtures("customer_list_payment_methods_empty_response.json")
    )
  end

  it "soft deletes provider customers on destroy and recreates them on reconnect" do
    provider = create(:stripe_provider, organization:)
    create_or_update_customer({
      external_id: customer.external_id,
      billing_configuration: {
        payment_provider: "stripe",
        payment_provider_code: provider.code,
        provider_customer_id: "cus_old"
      }
    })
    provider_customer = customer.stripe_customer
    expect(provider_customer.payment_provider_id).to eq(provider.id)

    PaymentProviders::DestroyService.call(provider)

    expect(provider.reload).to be_discarded
    expect(provider_customer.reload).to be_discarded
    expect(provider_customer.payment_provider_id).to eq(provider.id)

    new_provider = create(:stripe_provider, organization:, code: "stripe_reconnected")
    create_or_update_customer({
      external_id: customer.external_id,
      billing_configuration: {
        payment_provider: "stripe",
        payment_provider_code: new_provider.code,
        provider_customer_id: "cus_new"
      }
    })

    new_provider_customer = customer.reload.stripe_customer
    expect(new_provider_customer).not_to eq(provider_customer)
    expect(new_provider_customer.payment_provider_id).to eq(new_provider.id)
    expect(new_provider_customer.provider_customer_id).to eq("cus_new")

    expect(PaymentProviderCustomers::StripeCustomer.where(customer_id: customer.id)).to eq([new_provider_customer])
    expect(PaymentProviderCustomers::StripeCustomer.with_discarded.where(customer_id: customer.id))
      .to match_array([provider_customer, new_provider_customer])
  end

  it "charges a pending invoice payment through the reconnected provider customer", :premium do
    add_on = create(:add_on, organization:, amount_cents: 10_000)
    invoice = Invoice.find(create_one_off_invoice(customer, [add_on])[:invoice][:lago_id])
    expect(invoice.total_amount_cents).to eq(10_000)

    provider = create(:stripe_provider, organization:)
    create_or_update_customer({
      external_id: customer.external_id,
      billing_configuration: {
        payment_provider: "stripe",
        payment_provider_code: provider.code,
        provider_customer_id: "cus_old"
      }
    })
    old_provider_customer = customer.reload.stripe_customer

    # A previous attempt left a pending payment on the old provider customer, for the full total.
    pending_payment = create(
      :payment,
      payable: invoice,
      customer:,
      organization:,
      payment_provider: provider,
      payment_provider_customer: old_provider_customer,
      amount_cents: 10_000,
      amount_currency: invoice.currency,
      status: "pending",
      payable_payment_status: "pending"
    )

    create_payment(customer, invoice, 3_000)
    expect(invoice.reload.total_paid_amount_cents).to eq(3_000)

    PaymentProviders::DestroyService.call(provider)

    new_provider = create(:stripe_provider, organization:, code: "stripe_reconnected")
    create_or_update_customer({
      external_id: customer.external_id,
      billing_configuration: {
        payment_provider: "stripe",
        payment_provider_code: new_provider.code,
        provider_customer_id: "cus_new"
      }
    })
    new_provider_customer = customer.reload.stripe_customer
    create(:payment_method, payment_provider_customer: new_provider_customer, provider_method_id: "pm_new", is_default: true)

    stub_request(:get, "https://api.stripe.com/v1/customers/cus_new/payment_methods/pm_new").and_return(
      status: 200,
      body: get_stripe_fixtures("retrieve_payment_method_response.json") do |h|
        h["id"] = "pm_new"
        h["customer"] = "cus_new"
      end
    )

    stub_request(:post, "https://api.stripe.com/v1/payment_intents").and_return(
      status: 200, body: {id: "pi_reconnected", object: "payment_intent", status: "processing"}.to_json
    )

    retry_invoice_payment(invoice.id)

    # total 10_000 - partial payment 3_000
    expect(
      a_request(:post, "https://api.stripe.com/v1/payment_intents")
        .with(body: hash_including("customer" => "cus_new", "payment_method" => "pm_new", "amount" => (10_000 - 3_000).to_s))
    ).to have_been_made.once

    pending_payment.reload
    expect(pending_payment.payment_provider_id).to eq(new_provider.id)
    expect(pending_payment.payment_provider_customer_id).to eq(new_provider_customer.id)
    expect(pending_payment.amount_cents).to eq(7_000)
    expect(pending_payment.provider_payment_id).to eq("pi_reconnected")
  end
end
