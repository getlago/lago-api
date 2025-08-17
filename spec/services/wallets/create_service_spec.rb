# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::CreateService, type: :service do
  subject(:create_service) { described_class.new(params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:, external_id: "foobar", currency: customer_currency) }
  let(:customer_currency) { "EUR" }

  describe "#call" do
    let(:paid_credits) { "1.00" }
    let(:granted_credits) { "0.00" }
    let(:expiration_at) { (Time.current + 1.year).iso8601 }

    let(:params) do
      {
        name: "New Wallet",
        customer:,
        organization_id: organization.id,
        currency: "EUR",
        rate_amount: "1.00",
        expiration_at:,
        paid_credits:,
        granted_credits:
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
        expect(wallet.currency).to eq("EUR")
        expect(wallet.rate_amount).to eq(1.0)
        expect(wallet.expiration_at.iso8601).to eq(expiration_at)
        expect(wallet.recurring_transaction_rules.count).to eq(0)
        expect(wallet.invoice_requires_successful_payment).to eq(false)
      end
    end

    it "sends `wallet.created` webhook" do
      expect { service_result }
        .to have_enqueued_job(SendWebhookJob).with("wallet.created", Wallet)
    end

    it "produces an activity log" do
      wallet = described_class.call(params:).wallet

      expect(Utils::ActivityLog).to have_produced("wallet.created").after_commit.with(wallet)
    end

    it "enqueues the WalletTransaction::CreateJob" do
      expect { service_result }
        .to have_enqueued_job(WalletTransactions::CreateJob)
    end

    context "with validation error" do
      let(:paid_credits) { "-15.00" }

      it "returns an error" do
        expect(service_result).not_to be_success
        expect(service_result.error.messages[:paid_credits]).to eq(["invalid_paid_credits"])
      end
    end

    context "when invoice_requires_successful_payment is set " do
      let(:params) do
        {
          name: "New Wallet",
          customer:,
          organization_id: organization.id,
          currency: "EUR",
          rate_amount: "1.00",
          paid_credits:,
          invoice_requires_successful_payment: true
        }
      end

      it "follows the value" do
        aggregate_failures do
          expect { service_result }.to change(Wallet, :count).by(1)

          expect(service_result).to be_success

          wallet = service_result.wallet
          expect(wallet.invoice_requires_successful_payment).to eq(true)
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
          recurring_transaction_rules: rules
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
