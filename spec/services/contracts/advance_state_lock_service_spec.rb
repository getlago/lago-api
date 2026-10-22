# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::AdvanceStateLockService do
  subject(:lock_service) { described_class.new(contract:, product:, timeout_seconds: 0.seconds) }

  let(:organization) { create(:organization) }
  let(:contract) { create(:contract, organization:) }
  let(:product) { create(:product, :metered, organization:) }

  describe "#call" do
    context "when no transaction is open", transaction: false do
      let(:held_advisory_locks) do
        "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND granted AND pid = pg_backend_pid()"
      end

      it "holds the lock until the block returns, without opening a transaction" do
        lock_service.call do
          expect(ApplicationRecord.connection).not_to be_transaction_open
          expect(ApplicationRecord.connection.select_value(held_advisory_locks)).to eq(1)
        end

        expect(ApplicationRecord.connection.select_value(held_advisory_locks)).to eq(0)
      end
    end

    context "when the contract product is already locked", transaction: false do
      around do |test|
        with_advisory_lock("contract-#{contract.id}-product-#{product.id}-advance-state", lock_released_after: 2.seconds) do
          test.run
        end
      end

      it "raises a BaseLockService::FailedToAcquireLock error" do
        expect { lock_service.call { nil } }.to raise_error(
          BaseLockService::FailedToAcquireLock,
          "Failed to acquire lock contract-#{contract.id}-product-#{product.id}-advance-state"
        )
      end

      it "does not block another product of the contract" do
        other_product = create(:product, :metered, organization:)

        expect(described_class.new(contract:, product: other_product, timeout_seconds: 0.seconds).call { :priced }.value)
          .to eq(:priced)
      end
    end
  end
end
