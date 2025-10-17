# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::CreateService do
  subject(:create_service) { described_class.new(params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:, external_id: "foobar", currency: customer_currency) }
  let(:customer_currency) { "EUR" }

  describe "#call" do
    let(:paid_credits) { "1.00" }
    let(:granted_credits) { "0.00" }
    let(:expiration_at) { (Time.current + 1.year).iso8601 }
    let(:ignore_paid_top_up_limits_on_creation) { nil }

    let(:params) do
      {
        name: "New Wallet",
        priority: 5,
        customer:,
        organization_id: organization.id,
        currency: "EUR",
        rate_amount: "5.00",
        expiration_at:,
        paid_credits:,
        granted_credits:,
        paid_top_up_min_amount_cents: 1_00,
        paid_top_up_max_amount_cents: 1_000_00,
        ignore_paid_top_up_limits_on_creation:
      }
    end

    let(:service_result) { create_service.call }

    it "creates a wallet" do
      aggregate_failures do
        expect { service_result }.to change(Wallet, :count).by(1)

        expect(service_result).to be_success

        wallet = service_result.wallet
        expect(wallet.customer_id).to eq(customer.id)
        expect(wallet.name).to eq("New Wallet")
        expect(wallet.priority).to eq(5)
        expect(wallet.currency).to eq("EUR")
        expect(wallet.rate_amount).to eq(5.0)
        expect(wallet.expiration_at.iso8601).to eq(expiration_at)
        expect(wallet.recurring_transaction_rules.count).to eq(0)
        expect(wallet.invoice_requires_successful_payment).to eq(false)
        expect(wallet.paid_top_up_min_amount_cents).to eq(1_00)
        expect(wallet.paid_top_up_max_amount_cents).to eq(1_000_00)
      end
    end

    it "sends `wallet.created` webhook" do
      expect { service_result }.to have_enqueued_job(SendWebhookJob).with("wallet.created", Wallet)
    end

    it "produces an activity log" do
      wallet = described_class.call(params:).wallet

      expect(Utils::ActivityLog).to have_produced("wallet.created").after_commit.with(wallet)
    end

    it "enqueues the WalletTransaction::CreateJob" do
      expect { service_result }.to have_enqueued_job(WalletTransactions::CreateJob)
    end

    context "with validation error" do
      let(:paid_credits) { "-15.00" }

      it "returns an error" do
        expect(service_result).not_to be_success
        expect(service_result.error.messages[:paid_credits]).to eq(["invalid_paid_credits", "invalid_amount"])
      end
    end

    context "when customer has reached the wallet limit" do
      before do
        create_list(:wallet, 5, customer:, organization:, status: :active)
      end

      it "returns an error" do
        expect { service_result }.not_to change(Wallet, :count)
        expect(service_result).not_to be_success
        expect(service_result.error.messages[:customer]).to eq(["wallet_limit_reached"])
      end
    end

    context "when paid_credits is above the maximum" do
      let(:paid_credits) { "1002.0" }

      it "returns an error" do
        expect { service_result }.not_to change(organization.wallets, :count)
        expect(service_result).not_to be_success
        expect(service_result.error.messages[:paid_credits]).to eq(["amount_above_maximum"])
      end
    end

    context "when paid_credits is above the maximum and ignore validation flag passed" do
      let(:paid_credits) { "1002.0" }
      let(:ignore_paid_top_up_limits_on_creation) { "true" }

      it "returns an error" do
        perform_enqueued_jobs(only: WalletTransactions::CreateJob) do
          expect { service_result }.to change(organization.wallets, :count)
          expect(service_result).to be_success
          transaction = service_result.wallet.wallet_transactions.first
          expect(transaction).to have_attributes(credit_amount: 1002.00)
        end
      end
    end

    context "when priority is out of bounds" do
      let(:params) do
        {
          name: "New Wallet",
          customer:,
          organization_id: organization.id,
          currency: "EUR",
          rate_amount: "1.00",
          priority: 55
        }
      end

      it "defaults to 50" do
        expect(service_result).not_to be_success
        expect(service_result.error.messages[:priority]).to eq(["value_is_invalid"])
      end
    end

    context "when priority is not set" do
      let(:params) do
        {
          name: "New Wallet",
          customer:,
          organization_id: organization.id,
          currency: "EUR",
          rate_amount: "1.00"
        }
      end

      it "defaults to 50" do
        expect(service_result).to be_success

        wallet = service_result.wallet
        expect(wallet.priority).to eq(50)
      end
    end

    context "when invoice_requires_successful_payment is set" do
      let(:params) do
        {
          name: "New Wallet",
          customer:,
          organization_id: organization.id,
          currency: "EUR",
          rate_amount: "1.00",
          paid_credits:,
          invoice_requires_successful_payment:
        }
      end
      let(:invoice_requires_successful_payment) { true }

      it "follows the value" do
        expect { service_result }.to change(Wallet, :count).by(1)

        expect(service_result).to be_success

        wallet = service_result.wallet
        expect(wallet.invoice_requires_successful_payment).to eq(true)
      end

      context "when invoice_requires_successful_payment is null" do
        let(:invoice_requires_successful_payment) { nil }

        it "defaults to false" do
          expect { service_result }.to change(Wallet, :count).by(1)

          expect(service_result).to be_success

          wallet = service_result.wallet
          expect(wallet.invoice_requires_successful_payment).to eq(false)
        end
      end
    end

    context "when customer does not have a currency" do
      let(:customer_currency) { nil }

      it "applies the currency to the customer" do
        service_result
        expect(customer.reload.currency).to eq("EUR")
      end

      context "when no currency is provided" do
        let(:params) do
          {
            name: "New Wallet",
            customer:,
            organization_id: organization.id,
            currency: nil,
            rate_amount: "1.00",
            expiration_at:,
            paid_credits:,
            granted_credits:
          }
        end

        it "returns an error" do
          expect(service_result).not_to be_success
          expect(service_result.error.messages[:currency]).to eq(["value_is_invalid"])
        end
      end
    end

    context "when wallet have transaction metadata" do
      let(:params) do
        {
          name: "New Wallet",
          customer:,
          organization_id: organization.id,
          currency: "EUR",
          rate_amount: "1.00",
          expiration_at:,
          paid_credits: "10",
          granted_credits: "10",
          transaction_metadata: [{"key" => "valid_value", "value" => "also_valid"}]
        }
      end

      it "enqueues the job with correct metadata" do
        expect { service_result }.to have_enqueued_job(
          WalletTransactions::CreateJob
        ).with(hash_including(
          params: hash_including(metadata: params[:transaction_metadata])
        ))
      end
    end

    context "when transaction_name is provided" do
      let(:params) do
        {
          name: "New Wallet",
          customer:,
          organization_id: organization.id,
          currency: "EUR",
          rate_amount: "1.00",
          expiration_at:,
          paid_credits:,
          granted_credits:,
          transaction_name: "Custom Transaction Name"
        }
      end

      it "enqueues the wallet transaction job with the transaction name" do
        expect { service_result }.to have_enqueued_job(
          WalletTransactions::CreateJob
        ).with(hash_including(
          params: hash_including(name: "Custom Transaction Name")
        ))
      end
    end

    context "with recurring transaction rules" do
      around { |test| lago_premium!(&test) }

      let(:rules) do
        [
          {
            interval: "monthly",
            method: "target",
            paid_credits: "10.0",
            granted_credits: "5.0",
            target_ongoing_balance: "100.0",
            trigger: "interval"
          }
        ]
      end
      let(:params) do
        {
          name: "New Wallet",
          customer:,
          organization_id: organization.id,
          currency: "EUR",
          rate_amount: "1.00",
          expiration_at:,
          paid_credits:,
          granted_credits:,
          recurring_transaction_rules: rules,
          paid_top_up_max_amount_cents: "5000"
        }
      end

      it "creates a wallet with recurring transaction rules" do
        aggregate_failures do
          expect { service_result }.to change(Wallet, :count).by(1)

          expect(service_result).to be_success
          wallet = service_result.wallet
          expect(wallet.name).to eq("New Wallet")
          expect(wallet.reload.recurring_transaction_rules.count).to eq(1)
        end
      end

      context "when recurring transaction rule has transaction_name" do
        let(:rules) do
          [
            {
              interval: "monthly",
              method: "target",
              paid_credits: "10.0",
              granted_credits: "5.0",
              target_ongoing_balance: "100.0",
              trigger: "interval",
              transaction_name: "Custom Top-up"
            }
          ]
        end

        it "creates a recurring rule with transaction_name" do
          expect { service_result }.to change(Wallet, :count).by(1)

          wallet = service_result.wallet
          expect(wallet.reload.recurring_transaction_rules.first.transaction_name).to eq("Custom Top-up")
        end
      end

      context "when number of rules is incorrect" do
        let(:rules) do
          [
            {
              trigger: "interval",
              interval: "monthly"
            },
            {
              trigger: "threshold",
              threshold_credits: "1.0"
            }
          ]
        end

        it "returns an error" do
          expect(service_result).not_to be_success
          expect(service_result.error.messages[:recurring_transaction_rules])
            .to eq(["invalid_number_of_recurring_rules"])
        end
      end

      context "when trigger is invalid" do
        let(:rules) do
          [
            {
              trigger: "invalid",
              interval: "monthly"
            }
          ]
        end

        it "returns an error" do
          expect(service_result).not_to be_success
          expect(service_result.error.messages[:recurring_transaction_rules]).to eq(["invalid_recurring_rule"])
        end
      end

      context "when threshold credits value is invalid" do
        let(:rules) do
          [
            {
              trigger: "threshold",
              threshold_credits: "abc"
            }
          ]
        end

        it "returns an error" do
          expect(service_result).not_to be_success
          expect(service_result.error.messages[:recurring_transaction_rules]).to eq(["invalid_recurring_rule"])
        end
      end

      context "when paid credits exceeds wallet limits" do
        let(:rules) do
          [
            {
              trigger: "interval",
              interval: "monthly",
              paid_credits: "100"
            }
          ]
        end

        it "returns an error" do
          expect(service_result).to be_failure
          expect(service_result.error.messages[:recurring_transaction_rules]).to eq(["invalid_recurring_rule"])
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
          name: "New Wallet",
          customer:,
          organization_id: organization.id,
          currency: "EUR",
          rate_amount: "1.00",
          expiration_at:,
          paid_credits:,
          granted_credits:,
          applies_to: limitations
        }
      end

      it "creates a wallet with correct limitations" do
        expect { service_result }.to change(Wallet, :count).by(1)
        expect(service_result).to be_success

        wallet = service_result.wallet
        expect(wallet.reload.name).to eq("New Wallet")
        expect(wallet.reload.allowed_fee_types).to eq(%w[charge])
      end

      context "when fee limitations are not correct" do
        let(:limitations) do
          {
            fee_types: %w[invalid]
          }
        end

        it "returns an error" do
          expect(service_result).not_to be_success
          expect(service_result.error.messages[:applies_to]).to eq(["invalid_limitations"])
        end
      end

      context "with billable metric limitations in graphql context" do
        let(:billable_metric) { create(:billable_metric, organization:) }
        let(:limitations) do
          {
            billable_metric_ids: [billable_metric.id]
          }
        end

        before { CurrentContext.source = "graphql" }

        it "creates a wallet" do
          expect { service_result }.to change(Wallet, :count).by(1)
          expect(service_result).to be_success
        end

        it "creates a wallet target" do
          expect { create_service.call }
            .to change(WalletTarget, :count).by(1)
        end

        context "with invalid billable metric" do
          let(:limitations) do
            {
              billable_metric_ids: [billable_metric.id, "invalid"]
            }
          end

          it "returns an error" do
            expect(service_result).not_to be_success
            expect(service_result.error.messages[:applies_to]).to eq(["invalid_limitations"])
          end
        end
      end

      context "with billable metric limitations in api context" do
        let(:billable_metric) { create(:billable_metric, organization:) }
        let(:limitations) do
          {
            billable_metric_codes: [billable_metric.code]
          }
        end

        before { CurrentContext.source = "api" }

        it "creates a wallet" do
          expect { service_result }.to change(Wallet, :count).by(1)
          expect(service_result).to be_success
        end

        it "creates a wallet target" do
          expect { create_service.call }
            .to change(WalletTarget, :count).by(1)
        end
      end
    end
  end
end
