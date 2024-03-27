# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::StripeCustomer, type: :model do
  subject(:stripe_customer) { described_class.new(attributes) }

  let(:attributes) {}

  describe "payment_method_id" do
    it "assigns and retrieve a payment method id" do
      stripe_customer.payment_method_id = "foo_bar"
      expect(stripe_customer.payment_method_id).to eq("foo_bar")
    end
  end

  describe "#provider_payment_methods" do
    subject(:provider_payment_methods) { stripe_customer.provider_payment_methods }

    let(:stripe_customer) { FactoryBot.build_stubbed(:stripe_customer) }

    let(:payment_methods) do
      described_class::PAYMENT_METHODS.sample Faker::Number.between(from: 1, to: 2)
    end

    before { stripe_customer.provider_payment_methods = payment_methods }

    it "returns provider payment methods" do
      expect(provider_payment_methods).to eq payment_methods
    end
  end

  describe "validation" do
    describe "of provider payment methods" do
      subject(:valid) { stripe_customer.valid? }

      let(:stripe_customer) do
        FactoryBot.build_stubbed(:stripe_customer, provider_payment_methods:)
      end

      let(:errors) { stripe_customer.errors }

      before { valid }

      context "when it is an empty array" do
        let(:provider_payment_methods) { [] }

        it "adds error on provider payment methods" do
          expect(errors.where(:provider_payment_methods, :blank)).to be_present
        end
      end

      context "when it is nil" do
        let(:provider_payment_methods) { nil }

        it "adds error on provider payment methods" do
          expect(errors.where(:provider_payment_methods, :blank)).to be_present
        end
      end

      context "when it contains only invalid value" do
        let(:provider_payment_methods) { %w[invalid] }

        it "adds error on provider payment methods" do
          expect(errors.where(:provider_payment_methods, :invalid)).to be_present
        end
      end

      context "when it contains both valid and invalid values" do
        let(:provider_payment_methods) { %w[card cash] }

        it "adds error on provider payment methods" do
          expect(errors.where(:provider_payment_methods, :invalid)).to be_present
        end
      end

      context "when it contains only valid value" do
        let(:provider_payment_methods) { %w[card] }

        it "does not add error on provider payment methods" do
          expect(errors.where(:provider_payment_methods, :invalid)).not_to be_present
        end
      end

      context "when it contains multiple valid values" do
        let(:provider_payment_methods) { described_class::PAYMENT_METHODS }

        it "does not add error on provider payment methods" do
          expect(errors.where(:provider_payment_methods, :invalid)).not_to be_present
        end
      end
    end
  end
end
