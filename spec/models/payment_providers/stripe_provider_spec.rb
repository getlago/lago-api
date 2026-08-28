# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::StripeProvider do
  subject(:stripe_provider) { build(:stripe_provider, attributes) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:customer) { create_default(:customer) }
  let(:attributes) {}

  it { is_expected.to validate_length_of(:success_redirect_url).is_at_most(1024).allow_nil }
  it { is_expected.to validate_presence_of(:name) }

  describe "validations" do
    it "validates uniqueness of the code" do
      expect(stripe_provider).to validate_uniqueness_of(:code).scoped_to(:organization_id)
    end
  end

  describe "secret_key" do
    it "assigns and retrieve a secret key" do
      stripe_provider.secret_key = "foo_bar"
      expect(stripe_provider.secret_key).to eq("foo_bar")
    end
  end

  describe "webhook_id" do
    it "assigns and retrieve a setting" do
      stripe_provider.webhook_id = "webhook_id"
      expect(stripe_provider.webhook_id).to eq("webhook_id")
    end
  end

  describe "webhook_secret" do
    it "assigns and retrieve a setting" do
      stripe_provider.webhook_secret = "secret"
      expect(stripe_provider.webhook_secret).to eq("secret")
    end
  end

  describe "#success_redirect_url" do
    let(:success_redirect_url) { Faker::Internet.url }

    before { stripe_provider.success_redirect_url = success_redirect_url }

    it "returns the url" do
      expect(stripe_provider.success_redirect_url).to eq success_redirect_url
    end
  end

  describe "#retriable_authentication_failure?" do
    subject(:method_call) { stripe_provider.retriable_authentication_failure?(error_code, payment:) }

    let(:error_code) { described_class::NEED_3DS_ERROR_CODE }
    let(:payment) { create(:payment, payable: create(:invoice)) }

    context "when the error is not an authentication failure" do
      let(:error_code) { "card_declined" }

      before { stripe_provider.supports_3ds = true }

      it "returns false" do
        expect(method_call).to eq(false)
      end
    end

    context "when the connection supports 3DS" do
      before { stripe_provider.supports_3ds = true }

      it "returns true" do
        expect(method_call).to eq(true)
      end
    end

    context "when the connection does not support 3DS" do
      it "returns false" do
        expect(method_call).to eq(false)
      end

      context "when the payment activates a payment-gated subscription" do
        before { allow(payment).to receive(:gated_subscription_activation?).and_return(true) }

        it "returns true" do
          expect(method_call).to eq(true)
        end
      end
    end
  end

  describe "require_terms_of_service_consent" do
    it "assigns and retrieve a setting" do
      stripe_provider.require_terms_of_service_consent = true
      expect(stripe_provider.require_terms_of_service_consent).to eq(true)
    end

    it "defaults to false when not set" do
      expect(stripe_provider.require_terms_of_service_consent).to be(false)
    end
  end
end
