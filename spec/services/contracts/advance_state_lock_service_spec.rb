# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::AdvanceStateLockService do
  subject(:lock_service) { described_class.new(contract:, product:, product_filter:, timeout_seconds: 0.seconds) }

  let(:organization) { create(:organization) }
  let(:contract) { create(:contract, organization:) }
  let(:product) { create(:product, :metered, organization:) }
  let(:product_filter) { create(:product_filter, organization:, product:) }

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

    context "when the contract product filter is already locked", transaction: false do
      let(:lock_key) { "contract-#{contract.id}-product-#{product.id}-filter-#{product_filter.id}-advance-state" }

      around do |test|
        with_advisory_lock(lock_key, lock_released_after: 2.seconds) { test.run }
      end

      it "raises a BaseLockService::FailedToAcquireLock error" do
        expect { lock_service.call { nil } }
          .to raise_error(BaseLockService::FailedToAcquireLock, "Failed to acquire lock #{lock_key}")
      end

      it "does not block another filter of the product" do
        other_filter = create(:product_filter, organization:, product:)

        expect(lock_for(product_filter: other_filter).call { :priced }.value).to eq(:priced)
      end

      it "does not block the product's card without a filter" do
        expect(lock_for(product_filter: nil).call { :priced }.value).to eq(:priced)
      end

      it "does not block another product of the contract" do
        other_product = create(:product, :metered, organization:)

        expect(lock_for(product: other_product, product_filter: nil).call { :priced }.value).to eq(:priced)
      end
    end

    context "when the product's card without a filter is already locked", transaction: false do
      let(:product_filter) { nil }
      let(:lock_key) { "contract-#{contract.id}-product-#{product.id}-filter-default-advance-state" }

      around do |test|
        with_advisory_lock(lock_key, lock_released_after: 2.seconds) { test.run }
      end

      it "raises a BaseLockService::FailedToAcquireLock error" do
        expect { lock_service.call { nil } }
          .to raise_error(BaseLockService::FailedToAcquireLock, "Failed to acquire lock #{lock_key}")
      end
    end
  end

  def lock_for(product_filter:, product: self.product)
    described_class.new(contract:, product:, product_filter:, timeout_seconds: 0.seconds)
  end
end
