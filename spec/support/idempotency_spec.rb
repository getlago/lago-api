# frozen_string_literal: true

require "rails_helper"

RSpec.describe Idempotency do
  describe ".idempotent_transaction" do
    let(:customer) { create(:customer) }

    context "when no components are added" do
      it "raises an ArgumentError" do
        expect do
          described_class.idempotent_transaction do
            # No components added
          end
        end.to raise_error(ArgumentError, "At least one component must be added with Idempotency.add")
      end
    end

    context "when operation succeeds" do
      it "executes the block" do
        block_executed = false

        described_class.idempotent_transaction do
          block_executed = true
          described_class.add("component")
        end

        expect(block_executed).to be true
      end

      it "creates an idempotency record with the correct key" do
        # Using a uniquely identifiable component
        unique_component = "unique-#{SecureRandom.uuid}"

        described_class.idempotent_transaction do
          described_class.add(unique_component)
        end

        expected_key = Digest::SHA256.hexdigest([unique_component].join("|"))
        expect(IdempotencyRecord.exists?(idempotency_key: expected_key)).to be true
      end

      it "creates an idempotency record with multiple components" do
        unique_prefix = SecureRandom.uuid
        component1 = "#{unique_prefix}-1"
        component2 = "#{unique_prefix}-2"

        described_class.idempotent_transaction do
          described_class.add(component1)
          described_class.add(component2)
        end

        expected_key = Digest::SHA256.hexdigest([component1, component2].join("|"))
        expect(IdempotencyRecord.exists?(idempotency_key: expected_key)).to be true
      end

      it "associates the resource with the idempotency record" do
        unique_component = "unique-#{SecureRandom.uuid}"

        described_class.idempotent_transaction do
          described_class.add(unique_component)
          described_class.resource = customer
        end

        expected_key = Digest::SHA256.hexdigest([unique_component].join("|"))
        idempotency_record = IdempotencyRecord.find_by(idempotency_key: expected_key)

        expect(idempotency_record.resource).to eq(customer)
      end

      it "returns the original result of the block" do
        block_return_value = "expected return value"

        result = described_class.idempotent_transaction do
          described_class.add("component-#{SecureRandom.uuid}")
          block_return_value
        end

        expect(result).to eq(block_return_value)
      end
    end

    context "when an idempotency error occurs" do
      it "rolls back the transaction and returns nil" do
        unique_component = "unique-#{SecureRandom.uuid}"

        transaction = Idempotency::Transaction.new
        transaction.components << unique_component
        IdempotencyRecords::CreateService.call!(idempotency_key: transaction.idempotency_key)

        result = described_class.idempotent_transaction do
          described_class.add(unique_component)
          "This won't be returned"
        end

        expected_key = Digest::SHA256.hexdigest([unique_component].join("|"))
        expect(IdempotencyRecord.exists?(idempotency_key: expected_key)).to be true
        expect(result).to be_nil
      end
    end

    context "when an exception occurs in the block" do
      it "cleans up the transaction context" do
        begin
          described_class.idempotent_transaction do
            described_class.add("component")
            raise "Test error"
          end
        rescue
          # Ignore the error
        end

        expect(described_class.current_transaction).to be_nil
      end

      it "propagates the exception" do
        expect do
          described_class.idempotent_transaction do
            described_class.add("component")
            raise "Test error"
          end
        end.to raise_error("Test error")
      end

      it "rolls back the database transaction" do
        unique_component = "unique-#{SecureRandom.uuid}"

        begin
          described_class.idempotent_transaction do
            described_class.add(unique_component)
            raise "Test error"
          end
        rescue
          # Ignore the error
        end

        expected_key = Digest::SHA256.hexdigest([unique_component].join("|"))
        expect(IdempotencyRecord.exists?(idempotency_key: expected_key)).to be false
      end
    end
  end

  describe ".add" do
    context "when called outside of a transaction" do
      it "raises an ArgumentError" do
        expect do
          described_class.add("component")
        end.to raise_error(ArgumentError, "Idempotency.add can only be called within an idempotent_transaction block")
      end
    end

    context "when called inside a transaction" do
      it "adds the component to the current transaction" do
        component_added = nil

        described_class.idempotent_transaction do
          described_class.add("test-component")
          component_added = described_class.current_transaction.components.first
        end

        expect(component_added).to eq("test-component")
      end
    end
  end

  describe ".resource=" do
    context "when called outside of a transaction" do
      it "raises an ArgumentError" do
        expect do
          described_class.resource = "resource"
        end.to raise_error(ArgumentError, "Idempotency.resource= can only be called within an idempotent_transaction block")
      end
    end

    context "when called inside a transaction" do
      it "sets the resource on the current transaction" do
        resource_value = create(:invoice)
        resource_set = nil

        described_class.idempotent_transaction do
          described_class.add("component")
          described_class.resource = resource_value
          resource_set = described_class.current_transaction.resource
        end

        expect(resource_set).to eq(resource_value)
      end
    end
  end

  describe "Transaction" do
    let(:transaction) { described_class::Transaction.new }

    describe "#idempotency_key" do
      it "generates a SHA256 hash of components joined by pipe" do
        transaction.components = ["one", "two", "three"]
        expected_key = Digest::SHA256.hexdigest(["one", "two", "three"].join("|"))

        expect(transaction.idempotency_key).to eq(expected_key)
      end

      it "handles components of different types" do
        transaction.components = [1, "two", :three, true]
        expected_key = Digest::SHA256.hexdigest(["1", "two", "three", "true"].join("|"))

        expect(transaction.idempotency_key).to eq(expected_key)
      end
    end

    describe "#valid?" do
      it "returns true when components are present" do
        transaction.components = ["component"]
        expect(transaction.valid?).to be true
      end

      it "returns false when components are empty" do
        expect(transaction.valid?).to be false
      end
    end
  end
end
