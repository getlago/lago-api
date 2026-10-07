# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::PaystackProvider do
  subject(:paystack_provider) { build(:paystack_provider) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:secret_key) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to allow_value(nil).for(:success_redirect_url) }
    it { is_expected.to allow_value("https://example.com/success").for(:success_redirect_url) }
    it { is_expected.not_to allow_value("invalid-url").for(:success_redirect_url) }
    it { is_expected.not_to allow_value("a" * 1025).for(:success_redirect_url) }

    it "validates uniqueness of the code" do
      expect(paystack_provider).to validate_uniqueness_of(:code).scoped_to(:organization_id)
    end
  end

  describe "constants" do
    it "defines success redirect URL" do
      expect(described_class::SUCCESS_REDIRECT_URL).to eq("https://paystack.com")
    end

    it "defines API URL" do
      expect(described_class::API_URL).to eq("https://api.paystack.co")
    end

    it "defines processing statuses" do
      expect(described_class::PROCESSING_STATUSES).to eq(%w[pending processing ongoing queued])
    end

    it "defines success statuses" do
      expect(described_class::SUCCESS_STATUSES).to eq(%w[success])
    end

    it "defines failed statuses" do
      expect(described_class::FAILED_STATUSES).to eq(%w[failed abandoned reversed])
    end

    it "defines supported currencies" do
      expect(described_class::SUPPORTED_CURRENCIES).to eq(%w[NGN GHS ZAR KES USD XOF])
    end
  end

  describe "#payment_type" do
    it "returns paystack" do
      expect(paystack_provider.payment_type).to eq("paystack")
    end
  end

  describe "#api_url" do
    it "returns the API URL" do
      expect(paystack_provider.api_url).to eq("https://api.paystack.co")
    end
  end

  describe "#webhook_end_point" do
    let(:lago_api_url) { "https://api.getlago.com" }

    before do
      allow(ENV).to receive(:[]).with("LAGO_API_URL").and_return(lago_api_url)
      paystack_provider.organization_id = SecureRandom.uuid
      paystack_provider.code = "paystack account"
    end

    it "returns the organization-scoped Paystack webhook endpoint" do
      expect(paystack_provider.webhook_end_point.to_s)
        .to eq("#{lago_api_url}/webhooks/paystack/#{paystack_provider.organization_id}?code=paystack+account")
    end
  end

  describe "#payable_payment_status" do
    it "maps Paystack statuses to Lago payment statuses" do
      expect(paystack_provider.payable_payment_status("success")).to eq("succeeded")
      expect(paystack_provider.payable_payment_status("failed")).to eq("failed")
      expect(paystack_provider.payable_payment_status("pending")).to eq("pending")
      expect(paystack_provider.payable_payment_status("unknown")).to be_nil
    end
  end

  describe ".supported_currency?" do
    it "checks Paystack-supported currencies case-insensitively" do
      expect(described_class.supported_currency?("ngn")).to be(true)
      expect(described_class.supported_currency?("EUR")).to be(false)
    end
  end

  describe "secrets accessors" do
    it "provides access to secret_key through secrets" do
      provider = create(:paystack_provider, secret_key: "sk_test_secret")

      expect(provider.secret_key).to eq("sk_test_secret")
    end
  end
end
