# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::ContractEntitlementUpdateService, transaction: false do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
  let(:other_contract) { create(:contract, organization:, customer:, catalog_plan:) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege) { create(:privilege, organization:, feature:, code: "max", value_type: "integer") }
  let(:locked) { Queue.new }
  let(:release) { Queue.new }

  before do
    privilege
    contract
    other_contract
  end

  # Frees a lock holder left waiting by a failed expectation.
  after { release << -> {} }

  def write(contract_id, value)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.call(
          contract: Contract.find(contract_id),
          entitlements_params: {feature.code => {privilege.code => value}}
        )
      end
    end
  end

  # Holds the contract row lock in another connection until `release` receives the block to run before the commit.
  def hold_contract_lock(contract_id)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction do
          Contract.lock("FOR NO KEY UPDATE").find(contract_id)
          locked << true
          release.pop.call
        end
      end
    end
  end

  describe "#call" do
    # Both writers must have read the contract entitlements before either inserts. Each one waits at the insert
    # for the other to arrive, for a bounded time, so a writer serialized behind the other does not hang.
    it "serializes two concurrent writes adding the same feature on one contract" do
      arrived = Queue.new

      allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
        arrived << true
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        sleep 0.05 while arrived.size < 2 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        original.call(*args, **kwargs)
      end

      results = [write(contract.id, 10), write(contract.id, 20)].map(&:value)

      expect(results).to all(be_success)
      expect(Entitlement::Entitlement.where(contract_id: contract.id, entitlement_feature_id: feature.id).count).to eq(1)
    end

    it "makes a write on the locked contract wait, and not a write on another contract" do
      holder = hold_contract_lock(contract.id)
      locked.pop

      other_writer = write(other_contract.id, 10)
      expect(other_writer.join(5)).to eq(other_writer)
      expect(other_writer.value).to be_success

      writer = write(contract.id, 20)
      expect(writer.join(0.5)).to be_nil

      release << -> {}
      holder.join
      expect(writer.value).to be_success
      expect(Entitlement::Entitlement.where(contract_id: contract.id, entitlement_feature_id: feature.id).count).to eq(1)
    end

    it "refuses a write waiting on a contract that the lock holder terminates" do
      holder = hold_contract_lock(contract.id)
      locked.pop

      writer = write(contract.id, 20)
      expect(writer.join(0.5)).to be_nil

      release << -> { Contract.where(id: contract.id).update_all(status: "terminated", terminated_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations
      holder.join
      result = writer.value

      expect(result).not_to be_success
      expect(result.error.messages).to eq(base: ["contract_not_editable"])
      expect(Entitlement::Entitlement.where(contract_id: contract.id)).to be_empty
    end
  end
end
