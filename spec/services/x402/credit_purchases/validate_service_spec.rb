# frozen_string_literal: true

require "rails_helper"

describe X402::CreditPurchases::ValidateService do
  subject(:result) { described_class.call(connection: x402_connection, params:, verified_payment:) }

  include_context "with an x402 payment"

  let(:plan) { create(:plan, organization:, amount_cents: 0, amount_currency: "USD") }
  let(:wallet_shape) { {name: "Agent credits", rate_amount: "0.001", currency: "USD"} }
  let(:params) { {plan_code: plan.code, wallet_code: "agent_credits", wallet: wallet_shape} }
  let(:verified_payment) { nil }

  context "without a verified payment" do
    it "passes" do
      expect(result).to be_success
    end

    context "without a plan code" do
      let(:params) { super().except(:plan_code) }

      it "refuses the plan code as mandatory" do
        expect(result.error.messages).to eq(plan_code: ["value_is_mandatory"])
      end
    end

    context "with a blank wallet code" do
      let(:params) { super().merge(wallet_code: "") }

      it "refuses the wallet code as mandatory" do
        expect(result.error.messages).to eq(wallet_code: ["value_is_mandatory"])
      end
    end

    context "with an unknown plan code" do
      let(:params) { super().merge(plan_code: "unknown") }

      it "fails with plan_not_found" do
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end

    context "with another organization's plan" do
      let(:plan) { create(:plan, amount_cents: 0, amount_currency: "USD") }

      it "fails with plan_not_found" do
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end

    context "with a deleted plan" do
      let(:plan) { create(:plan, organization:, deleted_at: Time.current) }

      it "fails with plan_not_found" do
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end

    context "with a wallet shape in another currency" do
      let(:wallet_shape) { super().merge(currency: "EUR") }

      it "passes, since the payer's wallet is not known yet" do
        expect(result).to be_success
      end
    end
  end

  context "with a verified payment" do
    let(:verified_payment) do
      X402::Settlements::VerifiedPayment.new(
        connection: x402_connection,
        payment_payload: X402::PaymentPayload.new(payment:, payment_requirements:),
        payer_address:,
        payment_digest: "digest",
        verify_response: {"isValid" => true}
      )
    end
    let(:payment) { x402_evm_payment }
    let(:payment_requirements) { x402_evm_requirements }
    let(:payer_address) { "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2" }
    let(:x402_evm_requirements) { super().merge("amount" => "10000000") }
    let(:x402_evm_payment) { super().deep_merge("payload" => {"authorization" => {"value" => "10000000"}}) }

    it "passes" do
      expect(result).to be_success
    end

    context "with an unknown plan code" do
      let(:params) { super().merge(plan_code: "unknown") }

      it "fails with plan_not_found" do
        expect(result.error.error_code).to eq("plan_not_found")
      end
    end

    context "with an unknown payer" do
      context "when the connection refuses strangers" do
        let(:x402_connection) { create(:x402_connection, organization:, auto_create_customers: false) }

        it "refuses with buyer_not_recognized" do
          expect(result.error.messages).to eq(base: ["buyer_not_recognized"])
        end
      end

      context "when a merchant's customer holds the derived external id" do
        let(:merchant_customer) { create(:customer, organization:, external_id: "x402_#{payer_address}") }

        before { merchant_customer }

        it "refuses with buyer_external_id_taken" do
          expect(result.error.messages).to eq(base: ["buyer_external_id_taken"])
        end

        context "with that customer discarded" do
          let(:merchant_customer) { create(:customer, organization:, external_id: "x402_#{payer_address}", deleted_at: Time.current) }

          it "passes" do
            expect(result).to be_success
          end
        end
      end

      context "when another organization's customer holds the derived external id" do
        before { create(:customer, external_id: "x402_#{payer_address}") }

        it "passes" do
          expect(result).to be_success
        end
      end

      context "without a wallet shape" do
        let(:params) { super().except(:wallet) }

        it "refuses the wallet as mandatory" do
          expect(result.error.messages).to eq(wallet: ["value_is_mandatory"])
        end
      end

      context "with a wallet shape that is not an object" do
        let(:wallet_shape) { "agent_credits" }

        it "refuses the wallet as mandatory" do
          expect(result.error.messages).to eq(wallet: ["value_is_mandatory"])
        end
      end

      context "with a wallet shape in another currency" do
        let(:wallet_shape) { super().merge(currency: "EUR") }

        it "refuses the currency" do
          expect(result.error.messages).to eq(wallet: ["currency_not_supported"])
        end
      end

      context "with a lowercase currency" do
        let(:wallet_shape) { super().merge(currency: "usd") }

        it "refuses the currency" do
          expect(result.error.messages).to eq(wallet: ["currency_not_supported"])
        end
      end

      context "with a numeric rate amount" do
        let(:wallet_shape) { super().merge(rate_amount: 0.001) }

        it "passes" do
          expect(result).to be_success
        end
      end

      context "with a rate amount of zero" do
        let(:wallet_shape) { super().merge(rate_amount: "0") }

        it "refuses the rate" do
          expect(result.error.messages).to eq(wallet: ["invalid_rate_amount"])
        end
      end

      context "with a rate amount below the wallet's five decimals" do
        let(:wallet_shape) { super().merge(rate_amount: "0.000004") }

        it "refuses the rate" do
          expect(result.error.messages).to eq(wallet: ["invalid_rate_amount"])
        end
      end

      context "with the largest rate amount the wallet stores" do
        let(:wallet_shape) { super().merge(rate_amount: "9999999999999999999999999.99999") }

        it "passes" do
          expect(result).to be_success
        end
      end

      context "with a rate amount above what the wallet stores" do
        let(:wallet_shape) { super().merge(rate_amount: "1e25") }

        it "refuses the rate" do
          expect(result.error.messages).to eq(wallet: ["invalid_rate_amount"])
        end
      end

      context "with an infinite rate amount" do
        let(:wallet_shape) { super().merge(rate_amount: Float::INFINITY) }

        it "refuses the rate" do
          expect(result.error.messages).to eq(wallet: ["invalid_rate_amount"])
        end
      end

      context "with a rate amount that is not a number" do
        let(:wallet_shape) { super().merge(rate_amount: "abc") }

        it "refuses the rate" do
          expect(result.error.messages).to eq(wallet: ["invalid_rate_amount"])
        end
      end

      context "with a rate amount the wallet does not parse" do
        let(:wallet_shape) { super().merge(rate_amount: "1,5") }

        it "refuses the rate" do
          expect(result.error.messages).to eq(wallet: ["invalid_rate_amount"])
        end
      end

      context "with a boolean rate amount" do
        let(:wallet_shape) { super().merge(rate_amount: true) }

        it "refuses the rate" do
          expect(result.error.messages).to eq(wallet: ["invalid_rate_amount"])
        end
      end

      context "without a rate amount" do
        let(:wallet_shape) { super().except(:rate_amount) }

        it "refuses the rate" do
          expect(result.error.messages).to eq(wallet: ["invalid_rate_amount"])
        end
      end

      context "with top-up limits" do
        let(:wallet_shape) { super().merge(paid_top_up_min_amount_cents: 500, paid_top_up_max_amount_cents: "5000") }

        it "passes" do
          expect(result).to be_success
        end

        context "with the maximum below the payment" do
          let(:wallet_shape) { super().merge(paid_top_up_max_amount_cents: "999") }

          it "refuses the amount as amount_above_maximum" do
            expect(result.error.messages).to eq(payment_requirements: ["amount_above_maximum"])
          end
        end

        context "with the maximum equal to the payment" do
          let(:wallet_shape) { super().merge(paid_top_up_max_amount_cents: 1_000) }

          it "passes" do
            expect(result).to be_success
          end
        end

        context "with the maximum below the minimum" do
          let(:wallet_shape) { super().merge(paid_top_up_max_amount_cents: 400) }

          it "refuses the limits" do
            expect(result.error.messages).to eq(wallet: ["invalid_paid_top_up_limits"])
          end
        end

        context "with a minimum of zero" do
          let(:wallet_shape) { super().merge(paid_top_up_min_amount_cents: 0) }

          it "refuses the limits" do
            expect(result.error.messages).to eq(wallet: ["invalid_paid_top_up_limits"])
          end
        end

        context "with a fractional maximum" do
          let(:wallet_shape) { super().merge(paid_top_up_max_amount_cents: "5000.5") }

          it "refuses the limits" do
            expect(result.error.messages).to eq(wallet: ["invalid_paid_top_up_limits"])
          end
        end

        context "with a maximum beyond the column's range" do
          let(:wallet_shape) { super().merge(paid_top_up_max_amount_cents: 2**63) }

          it "refuses the limits" do
            expect(result.error.messages).to eq(wallet: ["invalid_paid_top_up_limits"])
          end
        end

        context "with an explicit null minimum" do
          let(:wallet_shape) { super().merge(paid_top_up_min_amount_cents: nil) }

          it "passes" do
            expect(result).to be_success
          end
        end
      end

      context "with every rule broken" do
        let(:wallet_shape) { {currency: "EUR", rate_amount: "-1", paid_top_up_max_amount_cents: 0} }

        it "lists each broken rule" do
          expect(result.error.messages).to eq(wallet: %w[currency_not_supported invalid_rate_amount invalid_paid_top_up_limits])
        end
      end
    end

    context "with a known payer" do
      let(:customer) { create(:customer, organization:, x402_agent_address: payer_address, external_id: "x402_#{payer_address}") }
      let(:external_subscription_id) { "x402_#{payer_address}_#{plan.code}" }

      before { customer }

      it "passes" do
        expect(result).to be_success
      end

      context "when the connection refuses strangers" do
        let(:x402_connection) { create(:x402_connection, organization:, auto_create_customers: false) }

        it "passes" do
          expect(result).to be_success
        end
      end

      context "without a wallet shape" do
        let(:params) { super().except(:wallet) }

        it "refuses the wallet as mandatory" do
          expect(result.error.messages).to eq(wallet: ["value_is_mandatory"])
        end
      end

      context "with the wallet terminated" do
        before { create(:wallet, :terminated, customer:, code: "agent_credits", currency: "USD", x402_enabled: true) }

        it "passes on the shape it will be recreated from" do
          expect(result).to be_success
        end

        context "with a shape maximum below the payment" do
          let(:wallet_shape) { super().merge(paid_top_up_max_amount_cents: 999) }

          it "refuses the amount as amount_above_maximum" do
            expect(result.error.messages).to eq(payment_requirements: ["amount_above_maximum"])
          end
        end

        context "without a wallet shape" do
          let(:params) { super().except(:wallet) }

          it "refuses the wallet as mandatory" do
            expect(result.error.messages).to eq(wallet: ["value_is_mandatory"])
          end
        end
      end

      context "with the customer at the wallet cap" do
        before { 6.times { |index| create(:wallet, customer:, code: "other_credits_#{index}", currency: "USD") } }

        it "refuses with wallet_limit_reached" do
          expect(result.error.messages).to eq(base: ["wallet_limit_reached"])
        end
      end

      context "with the requested wallet among the capped ones" do
        before do
          5.times { |index| create(:wallet, customer:, code: "other_credits_#{index}", currency: "USD") }
          create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true)
        end

        it "passes" do
          expect(result).to be_success
        end
      end

      context "with the customer one wallet below the cap" do
        before { 5.times { |index| create(:wallet, customer:, code: "other_credits_#{index}", currency: "USD") } }

        it "passes" do
          expect(result).to be_success
        end
      end

      context "with an organization capping wallets at one", :premium do
        let(:organization) { create(:organization, premium_integrations: ["events_targeting_wallets"], max_wallets: 1) }

        before { create(:wallet, customer:, code: "older_credits", currency: "USD") }

        it "refuses with wallet_limit_reached" do
          expect(result.error.messages).to eq(base: ["wallet_limit_reached"])
        end
      end

      context "with an x402 wallet" do
        let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true) }

        before { wallet }

        it "passes" do
          expect(result).to be_success
        end

        context "with x402 turned off on the wallet" do
          let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: false) }

          it "refuses with wallet_not_x402_enabled" do
            expect(result.error.messages).to eq(base: ["wallet_not_x402_enabled"])
          end
        end

        context "with a maximum top-up below the payment" do
          let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true, paid_top_up_max_amount_cents: 999) }

          it "refuses the amount as amount_above_maximum" do
            expect(result.error.messages).to eq(payment_requirements: ["amount_above_maximum"])
          end
        end

        context "with a maximum top-up equal to the payment" do
          let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true, paid_top_up_max_amount_cents: 1_000) }

          it "passes" do
            expect(result).to be_success
          end

          context "with sub-cent dust above it" do
            let(:x402_evm_requirements) { super().merge("amount" => "10005000") }
            let(:x402_evm_payment) { super().deep_merge("payload" => {"authorization" => {"value" => "10005000"}}) }

            it "passes on the floored cents" do
              expect(result).to be_success
            end
          end
        end

        context "with a minimum top-up above the payment" do
          let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true, paid_top_up_min_amount_cents: 5_000) }

          it "passes, since x402 waives the minimum" do
            expect(result).to be_success
          end
        end

        context "with a wallet shape in another currency" do
          let(:wallet_shape) { super().merge(currency: "EUR") }

          it "passes, since the shape is ignored" do
            expect(result).to be_success
          end
        end

        context "with a wallet shape maximum below the payment" do
          let(:wallet_shape) { super().merge(paid_top_up_max_amount_cents: 999) }

          it "passes, since the shape is ignored" do
            expect(result).to be_success
          end
        end

        context "without a wallet shape" do
          let(:params) { super().except(:wallet) }

          it "passes" do
            expect(result).to be_success
          end
        end
      end

      context "with a pending subscription for the plan" do
        before { create(:subscription, :pending, customer:, plan:, external_id: external_subscription_id) }

        it "refuses with subscription_not_active" do
          expect(result.error.messages).to eq(base: ["subscription_not_active"])
        end
      end

      context "with an incomplete subscription for the plan" do
        before { create(:subscription, :incomplete, customer:, plan:, external_id: external_subscription_id) }

        it "refuses with subscription_not_active" do
          expect(result.error.messages).to eq(base: ["subscription_not_active"])
        end
      end

      context "with an active subscription beside a pending one" do
        before do
          create(:subscription, customer:, plan:, external_id: external_subscription_id)
          create(:subscription, :pending, customer:, plan:, external_id: external_subscription_id)
        end

        it "passes" do
          expect(result).to be_success
        end
      end

      context "with a terminated subscription for the plan" do
        before { create(:subscription, :terminated, customer:, plan:, external_id: external_subscription_id) }

        it "passes, since the grant opens a new one" do
          expect(result).to be_success
        end
      end

      context "with a pending subscription for another plan" do
        before { create(:subscription, :pending, customer:, external_id: "x402_#{payer_address}_other_plan") }

        it "passes" do
          expect(result).to be_success
        end
      end
    end

    context "with a Solana payer" do
      let(:payment) { x402_svm_payment }
      let(:payment_requirements) { x402_svm_requirements }
      let(:payer_address) { x402_svm_payer }

      context "when a merchant's customer holds the derived external id" do
        before { create(:customer, organization:, external_id: "x402_#{x402_svm_payer}") }

        it "refuses with buyer_external_id_taken" do
          expect(result.error.messages).to eq(base: ["buyer_external_id_taken"])
        end
      end

      context "with a pending subscription for the plan" do
        let(:customer) { create(:customer, organization:, x402_agent_address: x402_svm_payer, external_id: "x402_#{x402_svm_payer}") }

        before { create(:subscription, :pending, customer:, plan:, external_id: "x402_#{x402_svm_payer}_#{plan.code}") }

        it "refuses with subscription_not_active" do
          expect(result.error.messages).to eq(base: ["subscription_not_active"])
        end
      end
    end
  end
end
