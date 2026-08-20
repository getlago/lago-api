# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::CreateOrUpdateBatchService do
  subject(:service) do
    described_class.call(customer:, payment_provider_customers:, new_customer:)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:new_customer) { false }

  describe "#call" do
    context "when the array is nil" do
      let(:payment_provider_customers) { nil }

      before { create(:stripe_customer, customer:, is_default: true) }

      it "does not change the connections" do
        expect { service }.not_to change { customer.payment_provider_customers.count }
      end
    end

    context "when creating the manual connection" do
      let(:payment_provider_customers) { [{type: "lago_manual", code: "lago_manual"}] }

      it "creates the reserved manual connection" do
        result = service

        expect(result).to be_success
        manual = customer.payment_provider_customers.by_code("lago_manual").first
        expect(manual.payment_provider_id).to be_nil
        expect(manual).to be_manual
      end
    end

    context "when a connection is omitted from the array" do
      let!(:existing) { create(:stripe_customer, customer:, is_default: true) }
      let(:payment_provider_customers) { [{type: "lago_manual", code: "lago_manual"}] }

      it "discards the omitted connection" do
        service

        expect(existing.reload).to be_discarded
        expect(customer.payment_provider_customers.by_code("lago_manual").first).to be_present
      end
    end

    context "when an existing connection is referenced by id" do
      let!(:existing) { create(:stripe_customer, customer:, code: "stripe_eu", is_default: true) }
      let(:payment_provider_customers) { [{id: existing.id, code: "stripe_renamed"}] }

      it "updates it instead of discarding it" do
        service

        expect(existing.reload).not_to be_discarded
        expect(existing.code).to eq("stripe_renamed")
      end
    end

    context "when creating a provider connection" do
      let(:stripe_provider) { create(:stripe_provider, organization:, code: "stripe_eu_account") }
      let(:payment_provider_customers) do
        [
          {
            code: "stripe_eu",
            payment_provider: "stripe",
            payment_provider_code: "stripe_eu_account",
            provider_customer_id: "cus_123",
            provider_payment_methods: ["card"]
          }
        ]
      end

      before { stripe_provider }

      it "creates the provider connection" do
        result = service

        expect(result).to be_success
        connection = customer.payment_provider_customers.by_code("stripe_eu").first
        expect(connection).to be_a(PaymentProviderCustomers::StripeCustomer)
        expect(connection.provider_customer_id).to eq("cus_123")
      end
    end
  end
end
