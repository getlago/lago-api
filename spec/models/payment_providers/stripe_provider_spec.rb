# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::StripeProvider do
  subject(:stripe_provider) { build(:stripe_provider, attributes) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:customer) { create_default(:customer) }
  let(:attributes) {}

  it { is_expected.to validate_length_of(:success_redirect_url).is_at_most(1024).allow_nil }
  it { is_expected.to validate_presence_of(:name) }

  describe "stripe error classification" do
    it "splits stripe errors into transient and permanent, with no overlap" do
      transient = described_class::TRANSIENT_ERRORS
      permanent = described_class::PERMANENT_ERRORS

      expect(transient).to match_array([::Stripe::APIConnectionError, ::Stripe::APIError, ::Stripe::RateLimitError])
      expect(permanent).to match_array([::Stripe::AuthenticationError, ::Stripe::InvalidRequestError, ::Stripe::PermissionError])
      expect(transient & permanent).to be_empty
      expect(transient + permanent).to all(be < ::Stripe::StripeError)
    end
  end

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

  describe ".to_stripe_amount" do
    subject(:stripe_amount) { described_class.to_stripe_amount(amount_cents, currency) }

    let(:amount_cents) { 50_000 }

    %w[HUF ISK UGX].each do |override_currency|
      context "when the currency is #{override_currency}" do
        let(:currency) { override_currency }

        it "converts the amount to hundredths" do
          expect(stripe_amount).to eq(50_000 * 100) # Stripe reads #{override_currency} in hundredths
        end
      end
    end

    %w[EUR USD JPY].each do |other_currency|
      context "when the currency is #{other_currency}" do
        let(:currency) { other_currency }

        it "returns the amount unchanged" do
          expect(stripe_amount).to eq(50_000)
        end
      end
    end

    context "when the currency is lowercase" do
      let(:currency) { "huf" }

      it "converts the amount to hundredths" do
        expect(stripe_amount).to eq(50_000 * 100) # Stripe reads HUF in hundredths
      end
    end

    context "when the currency is a Symbol" do
      let(:currency) { :huf }

      it "converts the amount to hundredths" do
        expect(stripe_amount).to eq(50_000 * 100) # Stripe reads HUF in hundredths
      end
    end
  end

  describe ".from_stripe_amount" do
    subject(:lago_amount) { described_class.from_stripe_amount(amount, currency) }

    let(:amount) { 5_000_000 }

    %w[HUF ISK UGX].each do |override_currency|
      context "when the currency is #{override_currency}" do
        let(:currency) { override_currency }

        it "converts the amount back from hundredths" do
          expect(lago_amount).to eq(5_000_000 / 100) # Stripe sends #{override_currency} in hundredths
        end
      end
    end

    %w[EUR USD JPY].each do |other_currency|
      context "when the currency is #{other_currency}" do
        let(:currency) { other_currency }

        it "returns the amount unchanged" do
          expect(lago_amount).to eq(5_000_000)
        end
      end
    end

    context "when the currency is lowercase" do
      let(:currency) { "huf" }

      it "converts the amount back from hundredths" do
        expect(lago_amount).to eq(5_000_000 / 100) # Stripe sends HUF in hundredths
      end
    end

    context "when the currency is a Symbol" do
      let(:currency) { :huf }

      it "converts the amount back from hundredths" do
        expect(lago_amount).to eq(5_000_000 / 100) # Stripe sends HUF in hundredths
      end
    end

    context "when the amount is nil" do
      let(:amount) { nil }
      let(:currency) { "huf" }

      it "returns nil" do
        expect(lago_amount).to be_nil
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
