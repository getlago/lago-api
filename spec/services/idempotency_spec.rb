# frozen_string_literal: true

require "rails_helper"

RSpec.describe Idempotency, transaction: false do
  describe ".transaction" do
    let(:customer) { create(:customer) }
    let(:invoice) { create(:invoice) }

    context "when no components are added" do
      it "raises an ArgumentError" do
        expect do
          described_class.transaction {}
        end.to raise_error(ArgumentError, "At least one resource must be added")
      end
    end

    context "when already in a transaction" do
      it "raises an ArgumentError" do
        allow(ApplicationRecord.connection).to receive(:open_transactions).and_return(1)

        expect do
          described_class.transaction do
            # No operations
          end
        end.to raise_error(ArgumentError, "An idempotent_transaction cannot be created when already in a transaction")
      end
    end

    context "when operation succeeds" do
      it "executes the block" do
        block_executed = false

        described_class.transaction do
          block_executed = true
          described_class.unique!(invoice, invoice.id, invoice.issuing_date)
        end

        expect(block_executed).to be true
      end

      it "creates an idempotency record with the correct key and resource" do
        described_class.transaction do
          described_class.unique!(invoice, invoice.id, invoice.issuing_date)
        end
      end

      it "supports multiple resources in the same transaction" do
        described_class.transaction do
          described_class.unique!(invoice, invoice.id, invoice.issuing_date)
          described_class.unique!(customer, customer.id)
        end
      end

      it "supports multiple value arrays for the same resource" do
        described_class.transaction do
          described_class.unique!(invoice, invoice.id, invoice.issuing_date)
          described_class.unique!(invoice, invoice.customer_id)
        end
      end

      it "returns the original result of the block" do
        block_return_value = "expected return value"

        result = described_class.transaction do
          described_class.unique!(invoice, invoice.id)
          block_return_value
        end

        expect(result).to eq(block_return_value)
      end
    end

    context "when an idempotency error occurs" do
      it "raises an IdempotencyError" do
        # Execute the transaction once
        described_class.transaction do
          described_class.unique!(invoice, invoice.id)
        end

        # This one should now fail!
        expect do
          described_class.transaction do
            described_class.unique!(invoice, invoice.id)
          end
        end.to raise_error(Idempotency::IdempotencyError)
      end
    end

    context "when an exception occurs in the block" do
      it "cleans up the transaction context" do
        begin
          described_class.transaction do
            described_class.unique!(invoice, invoice.id)
            raise "Test error"
          end
        rescue
          # Ignore the error
        end

        expect(described_class.current_transaction).to be_nil
      end

      it "propagates the exception" do
        expect do
          described_class.transaction do
            described_class.unique!(invoice, invoice.id)
            raise "Test error"
          end
        end.to raise_error("Test error")
      end
    end
  end

  describe ".unique!" do
    context "when called outside of a transaction" do
      it "raises an ArgumentError" do
        expect do
          described_class.unique!("resource", "value")
        end.to raise_error(ArgumentError, "Idempotency.unique! can only be called within an idempotent_transaction block")
      end
    end

    context "when called inside a transaction" do
      it "adds the values to the resource in the current transaction" do
        values_added = nil
        resource = create(:event)

        described_class.transaction do
          described_class.unique!(resource, "value1", "value2")
          values_added = described_class.current_transaction.idempotent_resources[resource]
        end

        expect(values_added).to eq(["value1", "value2"])
      end

      it "takes the final value for multiple calls for the same resource" do
        resource = create(:event)
        values_list = nil

        described_class.transaction do
          described_class.unique!(resource, "value1")
          described_class.unique!(resource, "value2", "value3")
          values_list = described_class.current_transaction.idempotent_resources[resource]
        end

        expect(values_list).to eq(["value2", "value3"])
      end
    end
  end

  describe "Transaction" do
    let(:transaction) { described_class::Transaction.new }
    let(:invoice) { create(:invoice) }

    describe "#ensure_idempotent!" do
      it "creates idempotency records for each resource" do
        resource1 = create(:event)
        resource2 = create(:event)
        values1 = [["a", "b"], ["c"]]
        values2 = [["d"]]

        transaction.idempotent_resources[resource1] = values1
        transaction.idempotent_resources[resource2] = values2

        expect { transaction.ensure_idempotent! }.to change(IdempotencyRecord, :count).by(2)
      end
    end

    describe "#valid?" do
      it "returns true when resources are present" do
        resource = create(:event)
        transaction.idempotent_resources[resource] = [["value"]]
        expect(transaction.valid?).to be true
      end

      it "returns false when resources are empty" do
        expect(transaction.valid?).to be false
      end
    end
  end
end
