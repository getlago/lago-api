# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::RecurringTransactionRules::CreateService do
  subject(:create_service) { described_class.new(wallet:, wallet_params:) }

  let(:wallet) { create(:wallet, paid_top_up_min_amount_cents: 15_00) }
  let(:wallet_params) do
    {
      paid_credits: "100.0",
      granted_credits: "50.0",
      recurring_transaction_rules: [rule_params]
    }
  end

  let(:rule_params) do
    {
      interval: "monthly",
      method: "target",
      paid_credits: "10.0",
      granted_credits: "5.0",
      started_at: "2024-05-30T12:48:26Z",
      target_ongoing_balance: "100.0",
      trigger: "interval",
      ignore_paid_top_up_limits: "true"
    }
  end

  describe "#call" do
    context "when freemium" do
      it "does not create any recurring transaction rule" do
        expect { create_service.call }.not_to change { wallet.reload.recurring_transaction_rules.count }
      end
    end

    context "when premium" do
      around { |test| lago_premium!(&test) }

      it "creates rule with expected attributes" do
        expect { create_service.call }.to change { wallet.reload.recurring_transaction_rules.count }.by(1)

        expect(wallet.recurring_transaction_rules.first).to have_attributes(
          granted_credits: 5.0,
          interval: "monthly",
          method: "target",
          paid_credits: 10.0,
          started_at: Time.parse("2024-05-30T12:48:26Z"),
          target_ongoing_balance: 100.0,
          threshold_credits: 0.0,
          trigger: "interval",
          invoice_requires_successful_payment: false,
          ignore_paid_top_up_limits: true
        )
      end

      context "when method is fixed" do
        let(:rule_params) do
          {
            trigger: "threshold",
            threshold_credits: "1.0",
            paid_credits:
          }
        end

        context "when paid and granted credits are omitted for rule" do
          let(:rule_params) do
            {
              trigger: "threshold",
              threshold_credits: "1.0"
            }
          end

          it "creates rule with paid and granted credits amounts inherited from wallet" do
            expect { create_service.call }.to change { wallet.reload.recurring_transaction_rules.count }.by(1)

            expect(wallet.recurring_transaction_rules.first).to have_attributes(
              granted_credits: 50.0,
              method: "fixed",
              paid_credits: 100.0,
              target_ongoing_balance: nil,
              threshold_credits: 1.0,
              trigger: "threshold"
            )
          end
        end

        context "when paid credits amount aligned with wallet limits" do
          let(:paid_credits) { "15" }

          it "creates rule with expected attributes" do
            expect { create_service.call }.to change { wallet.reload.recurring_transaction_rules.count }.by(1)

            expect(wallet.recurring_transaction_rules.first).to have_attributes(
              granted_credits: 0.0,
              method: "fixed",
              paid_credits: 15.0,
              target_ongoing_balance: nil,
              threshold_credits: 1.0,
              trigger: "threshold"
            )
          end
        end

        context "when paid credits amount exceeds wallet limits" do
          let(:paid_credits) { "5" }

          it "fails with validation error" do
            expect { create_service.call }.not_to change { wallet.reload.recurring_transaction_rules.count }

            expect(create_service.call).to be_failure
            expect(create_service.call.error.messages).to match({recurring_transaction_rules: ["invalid_recurring_rule"]})
          end
        end

        context "when paid credits amount is zero" do
          let(:paid_credits) { "0" }

          it "creates rule with expected attributes" do
            expect { create_service.call }.to change { wallet.reload.recurring_transaction_rules.count }.by(1)

            expect(wallet.recurring_transaction_rules.first).to have_attributes(
              granted_credits: 0.0,
              method: "fixed",
              paid_credits: 0.0,
              target_ongoing_balance: nil,
              threshold_credits: 1.0,
              trigger: "threshold"
            )
          end
        end
      end

      context "when method is target" do
        let(:rule_params) do
          {
            trigger: "threshold",
            method: "target",
            threshold_credits: "1.0",
            paid_credits: "5"
          }
        end

        it "creates rule with expected attributes ignoring wallet limits" do
          expect { create_service.call }.to change { wallet.reload.recurring_transaction_rules.count }.by(1)

          expect(wallet.recurring_transaction_rules.first).to have_attributes(
            granted_credits: 0.0,
            method: "target",
            paid_credits: 5.0,
            target_ongoing_balance: nil,
            threshold_credits: 1.0,
            trigger: "threshold"
          )
        end
      end

      context "when invoice_requires_successful_payment is present" do
        let(:rule_params) do
          {
            trigger: "threshold",
            threshold_credits: "1.0",
            invoice_requires_successful_payment: true
          }
        end

        it "creates rule with expected attributes" do
          expect { create_service.call }.to change { wallet.reload.recurring_transaction_rules.count }.by(1)

          expect(wallet.recurring_transaction_rules.first).to have_attributes(
            invoice_requires_successful_payment: true
          )
        end
      end

      context "when transaction metadata is present" do
        let(:rule_params) do
          {
            trigger: "threshold",
            threshold_credits: "1.0",
            transaction_metadata:
          }
        end

        let(:transaction_metadata) { [{"key" => "valid_value", "value" => "also_valid"}] }

        it "creates rule with expected attributes" do
          expect { create_service.call }.to change { wallet.reload.recurring_transaction_rules.count }.by(1)

          expect(wallet.recurring_transaction_rules.first).to have_attributes(
            transaction_metadata: transaction_metadata
          )
        end
      end

      context "when invoice_requires_successful_payment is blank" do
        let(:wallet) { create(:wallet, invoice_requires_successful_payment: true) }
        let(:wallet_params) do
          {
            paid_credits: "100.0",
            granted_credits: "50.0",
            recurring_transaction_rules: [{
              trigger: "threshold",
              threshold_credits: "1.0"
            }]
          }
        end

        it "follows the wallet configuration" do
          expect { create_service.call }.to change { wallet.reload.recurring_transaction_rules.count }.by(1)

          expect(wallet.recurring_transaction_rules.first).to have_attributes(
            invoice_requires_successful_payment: true
          )
        end
      end

      context "when expiration_at is set in the rule" do
        let(:expiration_at) { (Time.current + 1.year).iso8601 }
        let(:wallet_params) do
          {
            paid_credits: "100.0",
            granted_credits: "50.0",
            recurring_transaction_rules: [{
              trigger: "threshold",
              threshold_credits: "1.0",
              expiration_at:
            }]
          }
        end

        it "creates a rule with the correct expiration_at" do
          expect { create_service.call }.to change { wallet.reload.recurring_transaction_rules.count }.by(1)
          expect(wallet.recurring_transaction_rules.first.expiration_at).to eq(expiration_at)
        end
      end

      {
        "Custom Top-up Name" => "Custom Top-up Name",
        "" => nil,
        "   " => nil,
        nil => nil
      }.each do |transaction_name, expected_transaction_name|
        context "when transaction_name is #{transaction_name.inspect}" do
          let(:rule_params) do
            {
              trigger: "threshold",
              threshold_credits: "1.0",
              transaction_name:
            }
          end

          it "creates rule with expected transaction_name" do
            expect { create_service.call }.to change { wallet.reload.recurring_transaction_rules.count }.by(1)

            expect(wallet.recurring_transaction_rules.first).to have_attributes(
              transaction_name: expected_transaction_name
            )
          end
        end
      end
    end
  end
end
