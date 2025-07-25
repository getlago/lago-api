# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::UpdateService, type: :service do
  subject(:update_service) { described_class.new(wallet:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:, allowed_fee_types: []) }
  let(:expiration_at) { (Time.current + 1.year).iso8601 }

  describe "#call" do
    before do
      subscription
      wallet
    end

    let(:params) do
      {
        id: wallet&.id,
        name: "new name",
        expiration_at:,
        invoice_requires_successful_payment: true
      }
    end

    it "updates the wallet" do
      result = described_class.call(wallet:, params:)
      expect(result).to be_success

      aggregate_failures do
        expect(result.wallet.name).to eq("new name")
        expect(result.wallet.expiration_at.iso8601).to eq(expiration_at)
        expect(result.wallet.invoice_requires_successful_payment).to eq(true)

        expect(SendWebhookJob).to have_been_enqueued.with("wallet.updated", Wallet)
        expect(Utils::ActivityLog).to have_produced("wallet.updated").after_commit.with(wallet)
      end
    end

    it "calls Wallets::Balance::RefreshOngoingService" do
      allow(Wallets::Balance::RefreshOngoingService).to receive(:call)
      update_service.call
      expect(Wallets::Balance::RefreshOngoingService).to have_received(:call).with(wallet:)
      expect(SendWebhookJob).to have_been_enqueued.with("wallet.updated", Wallet)
    end

    context "when wallet is not found" do
      let(:wallet) { nil }

      it "returns an error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("wallet_not_found")

        expect(SendWebhookJob).not_to have_been_enqueued.with("wallet.updated", Wallet)
      end
    end

    context "with invalid expiration_at" do
      context "when string cannot be parsed to date" do
        let(:expiration_at) { "invalid" }

        it "returns false and result has errors" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:expiration_at]).to eq(["invalid_date"])

          expect(SendWebhookJob).not_to have_been_enqueued.with("wallet.updated", Wallet)
        end
      end

      context "when expiration_at is integer" do
        let(:expiration_at) { 123 }

        it "returns false and result has errors" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:expiration_at]).to eq(["invalid_date"])

          expect(SendWebhookJob).not_to have_been_enqueued.with("wallet.updated", Wallet)
        end
      end

      context "when expiration_at is less than current time" do
        let(:expiration_at) { (Time.current - 1.year).iso8601 }

        it "returns false and result has errors" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:expiration_at]).to eq(["invalid_date"])

          expect(SendWebhookJob).not_to have_been_enqueued.with("wallet.updated", Wallet)
        end
      end
    end

    context "with recurring transaction rules" do
      around { |test| lago_premium!(&test) }

      let(:recurring_transaction_rule) { create(:recurring_transaction_rule, wallet:) }
      let(:transaction_metadata) { [] }
      let(:rules) do
        [
          {
            trigger: "interval",
            interval: "weekly",
            paid_credits: "105",
            granted_credits: "105",
            transaction_metadata:
          }
        ]
      end
      let(:params) do
        {
          id: wallet.id,
          name: "new name",
          expiration_at:,
          recurring_transaction_rules: rules
        }
      end

      before { recurring_transaction_rule }

      it "creates a new rule and terminates the old one" do
        result = update_service.call

        aggregate_failures do
          expect(result).to be_success

          rule = result.wallet.reload.recurring_transaction_rules.active.first

          expect(result.wallet.reload.recurring_transaction_rules.active.count).to eq(1)
          expect(result.wallet.reload.recurring_transaction_rules.terminated.count).to eq(1)
          expect(rule.id).not_to eq(recurring_transaction_rule.id)
          expect(rule.trigger).to eq("interval")
          expect(rule.interval).to eq("weekly")
          expect(rule.threshold_credits).to eq(0.0)
          expect(rule.paid_credits).to eq(105.0)
          expect(rule.granted_credits).to eq(105.0)

          expect(SendWebhookJob).to have_been_enqueued.with("wallet.updated", Wallet)
        end
      end

      context "when editing existing interval rule" do
        let(:rules) do
          [
            {
              lago_id: recurring_transaction_rule.id,
              trigger: "interval",
              interval: "weekly",
              paid_credits: "105",
              granted_credits: "105"
            }
          ]
        end

        it "updates the rule" do
          result = update_service.call

          aggregate_failures do
            expect(result).to be_success

            rule = result.wallet.reload.recurring_transaction_rules.active.first

            expect(result.wallet.reload.recurring_transaction_rules.count).to eq(1)
            expect(result.wallet.reload.recurring_transaction_rules.active.count).to eq(1)
            expect(result.wallet.reload.recurring_transaction_rules.terminated.count).to eq(0)
            expect(rule.id).to eq(recurring_transaction_rule.id)
            expect(rule.trigger).to eq("interval")
            expect(rule.interval).to eq("weekly")
            expect(rule.threshold_credits).to eq(0.0)
            expect(rule.paid_credits).to eq(105.0)
            expect(rule.granted_credits).to eq(105.0)

            expect(SendWebhookJob).to have_been_enqueued.with("wallet.updated", Wallet)
          end
        end
      end

      context "when changing the rule into threshold one" do
        let(:rules) do
          [
            {
              lago_id: recurring_transaction_rule.id,
              trigger: "threshold",
              threshold_credits: "205",
              paid_credits: "105",
              granted_credits: "105"
            }
          ]
        end

        it "updates the rule" do
          result = update_service.call

          expect(result).to be_success

          rule = result.wallet.reload.recurring_transaction_rules.active.first

          aggregate_failures do
            expect(result.wallet.reload.recurring_transaction_rules.count).to eq(1)
            expect(result.wallet.reload.recurring_transaction_rules.active.count).to eq(1)
            expect(result.wallet.reload.recurring_transaction_rules.terminated.count).to eq(0)
            expect(rule.id).to eq(recurring_transaction_rule.id)
            expect(rule.trigger).to eq("threshold")
            expect(rule.threshold_credits).to eq(205.0)
            expect(rule.paid_credits).to eq(105.0)
            expect(rule.granted_credits).to eq(105.0)

            expect(SendWebhookJob).to have_been_enqueued.with("wallet.updated", Wallet)
          end
        end
      end

      context "when an empty array is sent as argument" do
        let(:rules) { [] }

        it "terminates all existing recurring transaction rules" do
          result = update_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.wallet.reload.recurring_transaction_rules.count).to eq(1)
            expect(result.wallet.reload.recurring_transaction_rules.active.count).to eq(0)
            expect(result.wallet.reload.recurring_transaction_rules.terminated.count).to eq(1)

            expect(SendWebhookJob).to have_been_enqueued.with("wallet.updated", Wallet)
          end
        end
      end

      context "when number of rules is incorrect" do
        let(:rules) do
          [
            {
              trigger: "interval",
              interval: "monthly",
              paid_credits: "105",
              granted_credits: "105"
            },
            {
              trigger: "threshold",
              threshold_credits: "1.0",
              paid_credits: "105",
              granted_credits: "105"
            }
          ]
        end

        it "returns an error" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:recurring_transaction_rules]).to eq(["invalid_number_of_recurring_rules"])

          expect(SendWebhookJob).not_to have_been_enqueued.with("wallet.updated", Wallet)
        end
      end

      context "when trigger is invalid" do
        let(:rules) do
          [
            {
              trigger: "invalid",
              interval: "monthly",
              paid_credits: "105",
              granted_credits: "105"
            }
          ]
        end

        it "returns an error" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:recurring_transaction_rules]).to eq(["invalid_recurring_rule"])

          expect(SendWebhookJob).not_to have_been_enqueued.with("wallet.updated", Wallet)
        end
      end

      context "when threshold credits value is invalid" do
        let(:rules) do
          [
            {
              trigger: "threshold",
              threshold_credits: "abc",
              paid_credits: "105",
              granted_credits: "105"
            }
          ]
        end

        it "returns an error" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:recurring_transaction_rules]).to eq(["invalid_recurring_rule"])

          expect(SendWebhookJob).not_to have_been_enqueued.with("wallet.updated", Wallet)
        end
      end

      context "when transaction_rule.transaction_metadata is hash" do
        let(:transaction_metadata) { {} }

        it "returns an error" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:recurring_transaction_rules]).to eq(["invalid_recurring_rule"])

          expect(SendWebhookJob).not_to have_been_enqueued.with("wallet.updated", Wallet)
        end
      end
    end

    context "with limitations" do
      let(:limitations) do
        {
          fee_types: %w[charge]
        }
      end
      let(:params) do
        {
          id: wallet.id,
          name: "new name",
          applies_to: limitations
        }
      end

      it "creates fee limitation" do
        result = update_service.call

        expect(result).to be_success
        expect(result.wallet.reload.name).to eq(params[:name])
        expect(result.wallet.reload.allowed_fee_types).to eq(limitations[:fee_types])
        expect(SendWebhookJob).to have_been_enqueued.with("wallet.updated", Wallet)
      end

      context "when an empty array is sent as argument" do
        let(:limitations) do
          {
            fee_types: []
          }
        end

        it "removes fee limitations" do
          result = update_service.call

          expect(result).to be_success
          expect(result.wallet.reload.name).to eq(params[:name])
          expect(result.wallet.reload.allowed_fee_types).to eq(limitations[:fee_types])
          expect(SendWebhookJob).to have_been_enqueued.with("wallet.updated", Wallet)
        end
      end

      context "when fee type is invalid" do
        let(:limitations) do
          {
            fee_types: %w[invalid]
          }
        end

        it "returns an error" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:allowed_fee_types]).to eq(["invalid_fee_types"])
          expect(SendWebhookJob).not_to have_been_enqueued.with("wallet.updated", Wallet)
        end
      end

      context "with new billable metric limitations" do
        let(:billable_metric) { create(:billable_metric, organization:) }
        let(:billable_metric_second) { create(:billable_metric, organization:) }
        let(:wallet_target) { create(:wallet_target, wallet:, billable_metric:) }
        let(:limitations) do
          {
            billable_metric_ids: [billable_metric.id, billable_metric_second.id]
          }
        end

        before do
          CurrentContext.source = "graphql"

          billable_metric_second
          wallet_target
        end

        it "creates new wallet target" do
          expect { update_service.call }.to change(WalletTarget, :count).by(1)
        end

        context "with API context" do
          let(:limitations) do
            {
              billable_metric_codes: [billable_metric.code, billable_metric_second.code]
            }
          end

          before { CurrentContext.source = "api" }

          it "creates new wallet target" do
            expect { update_service.call }.to change(WalletTarget, :count).by(1)
          end
        end

        context "with invalid billable metric" do
          let(:limitations) do
            {
              billable_metric_ids: [billable_metric.id, billable_metric_second.id, "invalid"]
            }
          end

          it "returns an error" do
            result = update_service.call

            expect(result).not_to be_success
            expect(result.error.messages[:billable_metrics]).to eq(["invalid_identifier"])
          end
        end
      end

      context "with wallet targets to delete" do
        let(:billable_metric) { create(:billable_metric, organization:) }
        let(:wallet_target) { create(:wallet_target, wallet:, billable_metric:) }
        let(:limitations) do
          {
            billable_metric_ids: []
          }
        end

        before do
          CurrentContext.source = "graphql"

          wallet_target
        end

        it "deletes a wallet target" do
          expect { update_service.call }.to change(WalletTarget, :count).by(-1)
        end
      end
    end
  end
end
