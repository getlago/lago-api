# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::AdyenProvider do
  subject(:provider) { build(:adyen_provider) }

  it { is_expected.to validate_length_of(:success_redirect_url).is_at_most(1024).allow_nil }
  it { is_expected.to validate_presence_of(:name) }

  describe "validations" do
    let(:errors) { provider.errors }

    it "validates uniqueness of the code" do
      expect(provider).to validate_uniqueness_of(:code).scoped_to(:organization_id)
    end

    describe "of success redirect url format" do
      subject(:provider) { build(:adyen_provider, success_redirect_url:) }

      before { provider.valid? }

      context "when it is valid url with http(s) scheme" do
        let(:success_redirect_url) { Faker::Internet.url }

        it "does not add an error" do
          expect(errors.where(:success_redirect_url, :url_invalid)).not_to be_present
        end
      end

      context "when it is valid url with custom scheme" do
        let(:success_redirect_url) { "my-app://your.package.name?param=12&p=7" }

        it "does not add an error" do
          expect(errors.where(:success_redirect_url, :url_invalid)).not_to be_present
        end
      end

      context "when it is nil" do
        let(:success_redirect_url) { nil }

        it "does not add an error" do
          expect(errors.where(:success_redirect_url, :url_invalid)).not_to be_present
        end
      end

      context "when it is an empty string" do
        let(:success_redirect_url) { "" }

        it "adds an error" do
          expect(errors.where(:success_redirect_url, :url_invalid)).to be_present
        end
      end

      context "when it is not valid url" do
        context "when it contains no scheme" do
          let(:success_redirect_url) { "your.package.name?param=12&p=7" }

          it "adds an error" do
            expect(errors.where(:success_redirect_url, :url_invalid)).to be_present
          end
        end

        context "when it contains only scheme" do
          let(:success_redirect_url) { "https://" }

          it "adds an error" do
            expect(errors.where(:success_redirect_url, :url_invalid)).to be_present
          end
        end

        context "when it is just a string" do
          let(:success_redirect_url) { "invalidurl" }

          it "adds an error" do
            expect(errors.where(:success_redirect_url, :url_invalid)).to be_present
          end
        end
      end
    end
  end

  describe "#api_key" do
    let(:api_key) { SecureRandom.uuid }

    before { provider.api_key = api_key }

    it "returns the api key" do
      expect(provider.api_key).to eq api_key
    end
  end

  describe "#merchant_account" do
    let(:merchant_account) { "TestECOM" }

    before { provider.merchant_account = merchant_account }

    it "returns the merchant account" do
      expect(provider.merchant_account).to eq merchant_account
    end
  end

  describe "#live_prefix" do
    let(:live_prefix) { Faker::Internet.domain_word }

    before { provider.live_prefix = live_prefix }

    it "returns the live prefix" do
      expect(provider.live_prefix).to eq live_prefix
    end
  end

  describe "#hmac_key" do
    let(:hmac_key) { SecureRandom.uuid }

    before { provider.hmac_key = hmac_key }

    it "returns the hmac key" do
      expect(provider.hmac_key).to eq hmac_key
    end
  end

  describe "#success_redirect_url" do
    let(:success_redirect_url) { Faker::Internet.url }

    before { provider.success_redirect_url = success_redirect_url }

    it "returns the url" do
      expect(provider.success_redirect_url).to eq success_redirect_url
    end
  end

  describe ".to_adyen_amount" do
    it "multiplies by 100 the currencies Adyen gives 2 decimals and Money none" do
      expect(described_class.to_adyen_amount(50_000, "HUF")).to eq(5_000_000) # 50000 * 10**(2 - 0)
      expect(described_class.to_adyen_amount(50_000, "CLP")).to eq(5_000_000) # 50000 * 10**(2 - 0)
      expect(described_class.to_adyen_amount(1_500, "ISK")).to eq(150_000) # 1500 * 10**(2 - 0)
    end

    it "divides by 100 the currencies Adyen gives no decimals and Money 2" do
      expect(described_class.to_adyen_amount(1_234_500, "IDR")).to eq(12_345) # 1234500 / 10**(2 - 0)
      expect(described_class.to_adyen_amount(1_234_500, "CVE")).to eq(12_345) # 1234500 / 10**(2 - 0)
    end

    it "rounds a sub-unit part half up" do
      expect(described_class.to_adyen_amount(12_350, "IDR")).to eq(124) # 12350 / 100 = 123.5, rounds half up to 124
      expect(described_class.to_adyen_amount(12_349, "IDR")).to eq(123) # 12349 / 100 = 123.49, rounds down to 123
    end

    it "keeps the amount of the other currencies" do
      expect(described_class.to_adyen_amount(1_000, "EUR")).to eq(1_000)
      expect(described_class.to_adyen_amount(1_000, "USD")).to eq(1_000)
      expect(described_class.to_adyen_amount(1_000, "JPY")).to eq(1_000)
    end

    it "converts a lower-case currency" do
      expect(described_class.to_adyen_amount(50_000, "huf")).to eq(5_000_000) # 50000 * 10**(2 - 0)
    end

    it "keeps the amount when the currency is blank" do
      expect(described_class.to_adyen_amount(1_000, nil)).to eq(1_000)
    end

    it "returns nil for a nil amount" do
      expect(described_class.to_adyen_amount(nil, "HUF")).to be_nil
    end
  end

  describe ".from_adyen_amount" do
    it "divides by 100 the currencies Adyen gives 2 decimals and Money none" do
      expect(described_class.from_adyen_amount(5_000_000, "HUF")).to eq(50_000) # 5000000 / 10**(2 - 0)
      expect(described_class.from_adyen_amount(5_000_000, "CLP")).to eq(50_000) # 5000000 / 10**(2 - 0)
      expect(described_class.from_adyen_amount(150_000, "ISK")).to eq(1_500) # 150000 / 10**(2 - 0)
    end

    it "multiplies by 100 the currencies Adyen gives no decimals and Money 2" do
      expect(described_class.from_adyen_amount(12_345, "IDR")).to eq(1_234_500) # 12345 * 10**(2 - 0)
      expect(described_class.from_adyen_amount(12_345, "CVE")).to eq(1_234_500) # 12345 * 10**(2 - 0)
      expect(described_class.from_adyen_amount(124, "IDR")).to eq(12_400) # 124 * 10**(2 - 0)
    end

    it "rounds a sub-unit part half up" do
      expect(described_class.from_adyen_amount(5_000_050, "HUF")).to eq(50_001) # 5000050 / 100 = 50000.5, rounds half up to 50001
      expect(described_class.from_adyen_amount(5_000_049, "HUF")).to eq(50_000) # 5000049 / 100 = 50000.49, rounds down to 50000
    end

    it "keeps the amount of the other currencies" do
      expect(described_class.from_adyen_amount(1_000, "EUR")).to eq(1_000)
      expect(described_class.from_adyen_amount(1_000, "USD")).to eq(1_000)
      expect(described_class.from_adyen_amount(1_000, "JPY")).to eq(1_000)
    end

    it "converts a lower-case currency" do
      expect(described_class.from_adyen_amount(5_000_000, "huf")).to eq(50_000) # 5000000 / 10**(2 - 0)
    end

    it "keeps the amount when the currency is blank" do
      expect(described_class.from_adyen_amount(1_000, nil)).to eq(1_000)
    end

    it "returns nil for a nil amount" do
      expect(described_class.from_adyen_amount(nil, "IDR")).to be_nil
    end
  end
end
