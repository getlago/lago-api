# frozen_string_literal: true

require "rails_helper"

describe Wallets::ValidateX402Service do
  subject(:validate_service) { described_class.new(result, **args) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:customer) { create_default(:customer) }

  let(:result) { Wallets::UpdateService::Result.new }
  let(:args) { {wallet:, x402_enabled: true} }
  let(:wallet) { create(:wallet, currency: "USD") }
  let(:redis_cache_url) { "redis://cache:6379" }
  let(:disable_wallet_refresh) { nil }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LAGO_REDIS_CACHE_URL").and_return(redis_cache_url)
    allow(ENV).to receive(:[]).with("LAGO_DISABLE_WALLET_REFRESH").and_return(disable_wallet_refresh)
  end

  describe "#valid?" do
    it "accepts an eligible wallet" do
      expect(validate_service).to be_valid
    end

    context "with a non-USD wallet" do
      let(:wallet) { create(:wallet, currency: "EUR") }

      it "refuses with the currency rule" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages).to eq(x402_enabled: ["currency_not_supported"])
      end
    end

    context "without a Redis cache" do
      let(:redis_cache_url) { nil }

      it "refuses with the refresh rule" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages).to eq(x402_enabled: ["wallet_refresh_unavailable"])
      end

      context "with a memcache server" do
        before { allow(ENV).to receive(:[]).with("LAGO_MEMCACHE_SERVERS").and_return("memcache:11211") }

        it "refuses with the refresh rule" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages).to eq(x402_enabled: ["wallet_refresh_unavailable"])
        end
      end
    end

    context "when the wallet refresh is disabled" do
      let(:disable_wallet_refresh) { "true" }

      it "refuses with the refresh rule" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages).to eq(x402_enabled: ["wallet_refresh_unavailable"])
      end
    end

    context "when LAGO_DISABLE_WALLET_REFRESH is set to another value" do
      let(:disable_wallet_refresh) { "1" }

      it "accepts the wallet" do
        expect(validate_service).to be_valid
      end
    end

    context "with an active recurring transaction rule" do
      before { create(:recurring_transaction_rule, wallet:) }

      it "refuses with the recurring rules rule" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages).to eq(x402_enabled: ["recurring_transaction_rules_not_supported"])
      end

      context "when the update terminates every rule" do
        let(:args) { {wallet:, x402_enabled: true, recurring_transaction_rules: []} }

        it "accepts the wallet" do
          expect(validate_service).to be_valid
        end
      end

      context "when the rules are sent as null" do
        let(:args) { {wallet:, x402_enabled: true, recurring_transaction_rules: nil} }

        it "refuses with the recurring rules rule" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages).to eq(x402_enabled: ["recurring_transaction_rules_not_supported"])
        end
      end
    end

    context "with a terminated recurring transaction rule" do
      before { create(:recurring_transaction_rule, wallet:, status: :terminated) }

      it "accepts the wallet" do
        expect(validate_service).to be_valid
      end
    end

    context "with recurring transaction rules sent" do
      let(:args) { {wallet:, x402_enabled: true, recurring_transaction_rules: [{trigger: "threshold", threshold_credits: "10.0", paid_credits: "20.0"}]} }

      it "refuses with the recurring rules rule" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages).to eq(x402_enabled: ["recurring_transaction_rules_not_supported"])
      end
    end

    context "with every rule broken" do
      let(:wallet) { create(:wallet, currency: "EUR") }
      let(:redis_cache_url) { nil }

      before { create(:recurring_transaction_rule, wallet:) }

      it "names every rule" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages).to eq(
          x402_enabled: %w[currency_not_supported wallet_refresh_unavailable recurring_transaction_rules_not_supported]
        )
      end
    end

    context "when x402_enabled is false" do
      let(:wallet) { create(:wallet, currency: "EUR") }
      let(:args) { {wallet:, x402_enabled: false} }

      it "checks nothing" do
        expect(validate_service).to be_valid
      end
    end

    context "when x402_enabled is blank" do
      let(:wallet) { create(:wallet, currency: "EUR") }
      let(:args) { {wallet:, x402_enabled: ""} }

      it "checks nothing" do
        expect(validate_service).to be_valid
      end
    end

    context "with an x402 wallet" do
      let(:wallet) { create(:wallet, currency: "EUR", x402_enabled: true) }

      context "when x402_enabled is sent again" do
        it "checks nothing" do
          expect(validate_service).to be_valid
        end
      end

      context "with recurring transaction rules sent" do
        let(:args) { {wallet:, recurring_transaction_rules: [{trigger: "interval", interval: "monthly", paid_credits: "20.0"}]} }

        it "refuses the rules" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages).to eq(recurring_transaction_rules: ["not_supported_for_x402_wallet"])
        end

        context "when the update turns x402 off" do
          let(:args) { {wallet:, x402_enabled: false, recurring_transaction_rules: [{trigger: "interval", interval: "monthly", paid_credits: "20.0"}]} }

          it "accepts the rules" do
            expect(validate_service).to be_valid
          end
        end
      end

      context "with an empty rule list" do
        let(:args) { {wallet:, recurring_transaction_rules: []} }

        it "accepts the update" do
          expect(validate_service).to be_valid
        end
      end
    end
  end
end
