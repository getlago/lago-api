# frozen_string_literal: true

require "rails_helper"

describe "Payment Provider Destroy And Reconnect Scenarios" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  before do
    # Linking a Stripe provider customer enqueues FetchDefaultPaymentMethodJob,
    # which reaches out to Stripe. Return a customer with no default and no cards
    # so the job resolves to no payment method without any real HTTP call.
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
end
