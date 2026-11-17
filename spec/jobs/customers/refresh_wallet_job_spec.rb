# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::RefreshWalletJob do
  before_all do
    create_default(:organization)
  end

  describe "queue routing" do
    let_it_be(:customer) { create(:customer) }

    context "when the customer's organization is in the dedicated list" do
      before { stub_const("Utils::DedicatedWorkerConfig::ORGANIZATION_IDS", [customer.organization_id]) }

      it "routes to the dedicated queue" do
        expect(described_class.new(customer).queue_name).to eq("dedicated_wallets")
      end
    end

    context "when the customer's organization is not in the dedicated list" do
      before { stub_const("Utils::DedicatedWorkerConfig::ORGANIZATION_IDS", ["some-other-org-id"]) }

      it "falls back to low_priority" do
        expect(described_class.new(customer).queue_name).to eq("low_priority")
      end
    end

    it_behaves_like "a configurable queue", "wallets", "SIDEKIQ_WALLETS", "low_priority" do
      let(:arguments) { customer }
    end

    context "when the dedicated list is empty" do
      before { stub_const("Utils::DedicatedWorkerConfig::ORGANIZATION_IDS", []) }

      it "falls back to low_priority" do
        expect(described_class.new(customer).queue_name).to eq("low_priority")
      end
    end
  end

  describe "#perform" do
    subject { described_class.perform_now(customer, wallet_ids:) }

    let(:organization) { customer.organization }
    let(:result) { Customers::RefreshWalletsService::Result.new }
    let(:wallet_ids) { nil }

    before do
      allow(Customers::RefreshWalletsService).to receive(:call).with(customer:).and_return(result)
    end

    context "when customer is not awaiting wallet refresh" do
      let_it_be(:customer) { create(:customer, awaiting_wallet_refresh: false) }

      it "does not call the Customers::RefreshWalletsService service" do
        subject
        expect(Customers::RefreshWalletsService).not_to have_received(:call)
      end

      context "when wallet_ids are provided" do
        let(:wallet_ids) { create_list(:wallet, 2, customer:).map(&:id) }

        it "still refreshes the whole customer" do
          subject
          expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
        end
      end
    end

    context "when customer is awaiting wallet refresh" do
      let_it_be(:customer) { create(:customer, awaiting_wallet_refresh: true) }

      context "when refresh customer's wallets succeeds" do
        it "calls the Customers::RefreshWalletsService service" do
          subject
          expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
        end
      end

      context "when wallet_ids are provided" do
        let(:wallet_ids) { create_list(:wallet, 2, customer:).map(&:id) }

        it "refreshes the whole customer" do
          subject
          expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
        end
      end

      context "when a tax_error error_detail already exists" do
        before do
          create(:error_detail, owner: customer, organization:, error_code: :tax_error)
        end

        it "does not call the Customers::RefreshWalletsService service" do
          subject
          expect(Customers::RefreshWalletsService).not_to have_received(:call)
        end
      end

      context "when refresh customer's wallets fails with a tax error" do
        let(:result) { Customers::RefreshWalletsService::Result.new.validation_failure!(errors: {tax_error: ["customerAddressCouldNotResolve"]}) }

        context "when the error is related to the customer's address" do
          it "creates a tax_error error_detail on the customer" do
            expect { subject }.to change { customer.error_details.tax_error.count }.by(1)
          end

          it "does not re-raise the error" do
            expect { subject }.not_to raise_error
          end
        end

        context "when the tax error is an unknown failure" do
          let(:result) { Customers::RefreshWalletsService::Result.new.validation_failure!(errors: {tax_error: ["failure"]}) }

          it "does not create an error_detail and re-raises the error" do
            expect { subject }.to raise_error(BaseService::ValidationFailure).and not_change { customer.error_details.count }
          end
        end
      end

      context "when refresh customer's wallets is throttled by the tax provider" do
        let(:error) do
          BaseService::TooManyProviderRequestsFailure.new(
            BaseService::Result.new,
            provider_name: :anrok,
            error: StandardError.new("too many requests")
          )
        end

        before do
          allow(Customers::RefreshWalletsService).to receive(:call).with(customer:).and_raise(error)
        end

        it "retries a bounded number of times then gives up without raising" do
          assert_performed_jobs(10, only: [described_class]) do
            expect { described_class.perform_later(customer) }.not_to raise_error
          end
        end

        context "with the uniqueness lock enforced" do
          around do |example|
            ActiveJob::Uniqueness.reset_manager!
            example.run
            described_class.unlock!(customer)
            ActiveJob::Uniqueness.test_mode!
          end

          it "releases the uniqueness lock when giving up" do
            assert_performed_jobs(10, only: [described_class]) do
              described_class.perform_later(customer)
            end

            expect { described_class.perform_later(customer) }.to change { enqueued_jobs.count }.by(1) # rubocop:disable RSpec/ExpectChange
          end
        end
      end

      context "when the tax provider fails to answer the draft tax request" do
        let(:customer) { create(:customer, awaiting_wallet_refresh:) }
        let(:awaiting_wallet_refresh) { true }
        let(:wallet) do
          create(:wallet, customer:, balance_cents: 1000, credits_balance: 10.0, ongoing_balance_cents: 1000, credits_ongoing_balance: 10.0, rate_amount: 1)
        end
        let(:integration) { create(:anrok_integration, organization: customer.organization) }
        let(:plan) { create(:plan, interval: "monthly") }
        let(:billable_metric) { create(:billable_metric, aggregation_type: "count_agg") }
        let(:subscription) { create(:subscription, plan:, customer:, started_at: 2.years.ago) }

        before do
          wallet
          create(:anrok_customer, integration:, customer:)
          create(:standard_charge, plan:, billable_metric:, properties: {amount: "3"})
          create(:netsuite_collection_mapping, integration:, mapping_type: :fallback_item, settings: {external_id: "1", external_account_code: "11", external_name: ""})
          create(:event, organization_id: customer.organization_id, subscription:, customer:, code: billable_metric.code, timestamp: Time.current, created_at: 1.hour.ago)

          allow(Customers::RefreshWalletsService).to receive(:call).and_call_original
        end

        Integrations::Aggregator::BaseService.retryable_errors.each do |error_class|
          context "when the error is #{error_class.name.demodulize.underscore.humanize.downcase}" do
            before { stub_nango_action_failing_with(error_class) }

            it "retries the job, then raises the error without a tax error or a webhook and keeps the customer flagged" do
              assert_performed_jobs(6, only: [described_class]) do
                expect { described_class.perform_later(customer) }.to raise_error(error_class)
              end

              expect(customer.reload.awaiting_wallet_refresh).to be(true)
              expect(customer.error_details).to be_empty
              expect(SendWebhookJob).not_to have_been_enqueued
              expect(wallet.reload.ongoing_balance_cents).to eq(1000)
            end

            context "when it is a top-up refresh of a customer not flagged before" do
              let(:awaiting_wallet_refresh) { false }

              it "flags the customer once the retries are used up, then raises the error" do
                assert_performed_jobs(6, only: [described_class]) do
                  expect { described_class.perform_later(customer, wallet_ids: [wallet.id]) }.to raise_error(error_class)
                end

                expect(customer.reload.awaiting_wallet_refresh).to be(true)
              end
            end
          end
        end

        context "when the customer has no active wallet" do
          let(:awaiting_wallet_refresh) { false }
          let(:wallet) { create(:wallet, :terminated, customer:) }

          before { stub_nango_action(status: 503, body: "") }

          it "raises the error without flagging the customer" do
            assert_performed_jobs(6, only: [described_class]) do
              expect { described_class.perform_later(customer, wallet_ids: [wallet.id]) }.to raise_error(Integrations::Aggregator::ServerError)
            end

            expect(customer.reload.awaiting_wallet_refresh).to be(false)
          end
        end

        context "when the provider answers with an HTTP 400" do
          before { stub_nango_action(status: 400, body: {error: {code: "bad_request", message: "Invalid input"}}.to_json) }

          it "does not retry and raises the tax error" do
            assert_performed_jobs(1, only: [described_class]) do
              expect { described_class.perform_later(customer) }.to raise_error(BaseService::ValidationFailure, /tax_error/)
            end

            expect(customer.reload.awaiting_wallet_refresh).to be(true)
          end
        end

        context "when the provider answers again on the retry" do
          before { stub_nango_action({status: 503, body: ""}, anrok_draft_taxes_answer(rate: 0.1)) }

          it "refreshes the wallets with the provider taxes and clears the flag" do
            assert_performed_jobs(2, only: [described_class]) do
              expect { described_class.perform_later(customer) }.not_to raise_error
            end

            wallet.reload
            expect(wallet.ongoing_usage_balance_cents).to eq(300 + 30) # 1 event x 3 usage fee + 10% provider tax
            expect(wallet.ongoing_balance_cents).to eq(1000 - 330) # balance - ongoing usage
            expect(wallet.credits_ongoing_balance).to eq(6.7) # 670 cents at rate 1
            expect(customer.reload.awaiting_wallet_refresh).to be(false)
          end
        end
      end

      context "when refresh customer's wallets fails with a non-tax error" do
        let(:result) { Customers::RefreshWalletsService::Result.new.validation_failure!(errors: {other_error: ["something"]}) }

        it "re-raises the error" do
          expect { subject }.to raise_error(BaseService::ValidationFailure)
        end
      end
    end
  end
end
