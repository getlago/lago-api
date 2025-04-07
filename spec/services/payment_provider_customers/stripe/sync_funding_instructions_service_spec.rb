# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::Stripe::SyncFundingInstructionsService do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:provider_customer_id) { "cus_Rw5Qso78STEap3" }
  let(:provider_customer) { create(:stripe_customer, customer:, provider_customer_id:, payment_provider: create(:stripe_provider, organization:), payment_method_id: nil) }

  describe "#call" do
    # TODO working on it
    # context "when customer has a default payment method in Stripe" do
    #   it do
    #     stub_request(:get, %r{/v1/customers/#{provider_customer_id}$}).and_return(
    #       status: 200, body: File.read(Rails.root.join("spec/fixtures/stripe/customer_with_default_payment_method.json"))
    #     )
    #
    #     result = subject.call
    #     expect(result.payment_method_id).to eq "pm_1R2DFsQ8iJWBZFaMw3LLbR0r"
    #   end
    # end
  end
end
