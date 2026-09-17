# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::RefreshWalletJob do
  describe "queue routing" do
    let(:customer) { create(:customer) }

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

    let(:customer) { create(:customer, awaiting_wallet_refresh:) }
    let(:organization) { customer.organization }
    let(:awaiting_wallet_refresh) { true }
    let(:result) { Customers::RefreshWalletsService::Result.new }
    let(:wallet_ids) { nil }

    before do
      allow(Customers::RefreshWalletsService).to receive(:call).with(customer:).and_return(result)
    end

    it "refreshes the customer's wallets" do
      subject

      expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
    end

    context "when wallet_ids are provided" do
      let(:awaiting_wallet_refresh) { false }
      let(:wallet_ids) { create_list(:wallet, 2, customer:).map(&:id) }

      it "forces the refresh of the whole customer" do
        subject

        expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
      end
    end

    [
      Integrations::Aggregator::OutOfMemoryError,
      Integrations::Aggregator::TaskInProgressError,
      Integrations::Aggregator::TaskExpiredError,
      Integrations::Aggregator::OrchestratorFailureError,
      Integrations::Aggregator::ServerContentionError,
      Integrations::Aggregator::TimeoutError
    ].each do |error_class|
      context "when the refresh fails with #{error_class.name.demodulize.underscore.humanize.downcase}" do
        before do
          allow(Customers::RefreshWalletsService).to receive(:call).with(customer:).and_raise(error_class)
        end

        it "raises the error and retries the job" do
          assert_performed_jobs(6, only: [described_class]) do
            expect do
              described_class.perform_later(customer)
            end.to raise_error(error_class)
          end
        end
      end
    end

    context "when another lane holds the customer's refresh lock" do
      before do
        allow(Customers::LockService).to receive(:call!).and_raise(BaseLockService::FailedToAcquireLock)
      end

      it "retries the job" do
        assert_performed_jobs(ApplicationJob::MAX_LOCK_RETRY_ATTEMPTS, only: [described_class]) do
          expect do
            described_class.perform_later(customer)
          end.to raise_error(BaseLockService::FailedToAcquireLock)
        end
      end
    end

    context "when the refresh is throttled by the tax provider" do
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
  end
end
