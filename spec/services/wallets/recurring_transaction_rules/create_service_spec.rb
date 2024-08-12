# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::RecurringTransactionRules::CreateService do
  subject(:create_service) { described_class.new(wallet:, wallet_params:) }

  let(:wallet) { create(:wallet) }
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
      trigger: "interval"
    }
  end

  describe "#call" do
    context 'when freemium' do
      it 'does not create any recurring transaction rule' do
        expect { create_service.call }.not_to change { wallet.reload.recurring_transaction_rules.count }
      end
    end

    context 'when premium' do
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
          invoice_requires_successful_payment: false
        )
      end

      context 'when method is fixed' do
        let(:rule_params) do
          {
            trigger: "threshold",
            threshold_credits: "1.0"
          }
        end

        it "creates rule with expected attributes" do
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

      context 'when invoice_requires_successful_payment is present' do
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

      context "when metadata is present" do
        let(:rule_params) do
          {
            trigger: "threshold",
            threshold_credits: "1.0",
            metadata:
          }
        end

        let(:metadata) { [{'key' => 'valid_value', 'value' => 'also_valid'}] }

        it "creates rule with expected attributes" do
          expect { create_service.call }.to change { wallet.reload.recurring_transaction_rules.count }.by(1)

          expect(wallet.recurring_transaction_rules.first).to have_attributes(
            metadata: metadata
          )
        end
      end

      context 'when invoice_requires_successful_payment is blank' do
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

        it 'follows the wallet configuration' do
          expect { create_service.call }.to change { wallet.reload.recurring_transaction_rules.count }.by(1)

          expect(wallet.recurring_transaction_rules.first).to have_attributes(
            invoice_requires_successful_payment: true
          )
        end
      end
    end
  end
end
