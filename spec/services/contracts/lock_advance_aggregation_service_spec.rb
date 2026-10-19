# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::LockAdvanceAggregationService do
  subject(:result) { described_class.call(metered_item:) { :completed } }

  let(:contract) { create(:contract) }
  let(:product) { create(:product, organization: contract.organization) }
  let(:metered_item) { Struct.new(:contract, :invoiceable).new(contract, product) }
  let(:lock_name) { "advance_aggregation_#{contract.id}_#{product.id}" }
  let(:other_product) { create(:product, organization: contract.organization) }
  let(:other_item) { Struct.new(:contract, :invoiceable).new(contract, other_product) }
  let(:other_lock_name) { "advance_aggregation_#{contract.id}_#{other_product.id}" }

  describe ".call" do
    it "holds the contract and product lock while the block runs, including inside a transaction" do
      expect(ActiveRecord::Base.advisory_lock_exists?(lock_name)).to be(false)

      result = described_class.call(metered_item:) do
        expect(ActiveRecord::Base.advisory_lock_exists?(lock_name)).to be(true)

        ApplicationRecord.transaction(requires_new: true) do
          expect(ApplicationRecord.connection.transaction_open?).to be(true)
          expect(ActiveRecord::Base.advisory_lock_exists?(lock_name)).to be(true)
        end

        :completed
      end

      expect(result.value).to eq(:completed)
      expect(ActiveRecord::Base.advisory_lock_exists?(lock_name)).to be(false)
    end

    it "reuses the same lock for the same contract and product" do
      described_class.call(metered_item:) do
        inner_result = described_class.call(metered_item:) { :inner }

        expect(inner_result.value).to eq(:inner)
        expect(ActiveRecord::Base.advisory_lock_exists?(lock_name)).to be(true)
      end
    end

    it "uses independent locks for different products on one contract" do
      described_class.call(metered_item:) do
        described_class.call(metered_item: other_item) do
          expect(ActiveRecord::Base.advisory_lock_exists?(lock_name)).to be(true)
          expect(ActiveRecord::Base.advisory_lock_exists?(other_lock_name)).to be(true)
        end

        expect(ActiveRecord::Base.advisory_lock_exists?(lock_name)).to be(true)
        expect(ActiveRecord::Base.advisory_lock_exists?(other_lock_name)).to be(false)
      end
    end

    context "without a contract" do
      let(:metered_item) { Struct.new(:contract, :invoiceable).new(nil, product) }

      it "yields without acquiring a lock" do
        allow(ActiveRecord::Base).to receive(:advisory_lock_exists?).and_call_original

        expect(result.value).to eq(:completed)
        expect(ActiveRecord::Base).not_to have_received(:advisory_lock_exists?)
      end
    end
  end
end
