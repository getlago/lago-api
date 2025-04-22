# frozen_string_literal: true

require "rails_helper"

RSpec.describe Idempotency do
  describe ".transaction" do
    let(:customer) { create(:customer) }
    let(:invoice) { create(:invoice) }

    context "when no components are added" do
      it "raises an ArgumentError" do
        expect do
          described_class.transaction do
            # No components added
          end
        end.to raise_error(ArgumentError, "At least one component must be added with Idempotency.add")
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
      before do
        # Mock necessary services
        allow(IdempotencyRecords::KeyService).to receive(:call!).and_return(OpenStruct.new(idempotency_key: "generated-key"))
        allow(IdempotencyRecords::CreateService).to receive(:call).and_return(OpenStruct.new(success?: true))
      end

      it "executes the block" do
        block_executed = false

        described_class.transaction do
          block_executed = true
          described_class.unique!(invoice, invoice.id, invoice.date)
        end

        expect(block_executed).to be true
      end

      it "calls the key service with the correct values" do
        date = Time.current
        invoice_id = 123
        
        expect(IdempotencyRecords::KeyService).to receive(:call!).with([invoice_id, date]).and_return(OpenStruct.new(idempotency_key: "generated-key"))

        described_class.transaction do
          described_class.unique!(invoice, invoice_id, date)
        end
      end

      it "creates an idempotency record with the correct key and resource" do
        expect(IdempotencyRecords::CreateService).to receive(:call).with(
          idempotency_key: "generated-key",
          resource: invoice
        ).and_return(OpenStruct.new(success?: true))

        described_class.transaction do
          described_class.unique!(invoice, invoice.id, invoice.date)
        end
      end

      it "supports multiple resources in the same transaction" do
        expect(IdempotencyRecords::KeyService).to receive(:call!).with([invoice.id, invoice.date]).and_return(OpenStruct.new(idempotency_key: "invoice-key"))
        expect(IdempotencyRecords::KeyService).to receive(:call!).with([customer.id]).and_return(OpenStruct.new(idempotency_key: "customer-key"))
        
        expect(IdempotencyRecords::CreateService).to receive(:call).with(
          idempotency_key: "invoice-key",
          resource: invoice
        ).and_return(OpenStruct.new(success?: true))
        
        expect(IdempotencyRecords::CreateService).to receive(:call).with(
          idempotency_key: "customer-key",
          resource: customer
        ).and_return(OpenStruct.new(success?: true))

        described_class.transaction do
          described_class.unique!(invoice, invoice.id, invoice.date)
          described_class.unique!(customer, customer.id)
        end
      end

      it "supports multiple value arrays for the same resource" do
        expect(IdempotencyRecords::KeyService).to receive(:call!).with([invoice.id, invoice.date]).and_return(OpenStruct.new(idempotency_key: "key1"))
        expect(IdempotencyRecords::KeyService).to receive(:call!).with([invoice.customer_id]).and_return(OpenStruct.new(idempotency_key: "key2"))
        
        expect(IdempotencyRecords::CreateService).to receive(:call).with(
          idempotency_key: "key1",
          resource: invoice
        ).and_return(OpenStruct.new(success?: true))
        
        expect(IdempotencyRecords::CreateService).to receive(:call).with(
          idempotency_key: "key2",
          resource: invoice
        ).and_return(OpenStruct.new(success?: true))

        described_class.transaction do
          described_class.unique!(invoice, invoice.id, invoice.date)
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
      before do
        allow(IdempotencyRecords::KeyService).to receive(:call!).and_return(OpenStruct.new(idempotency_key: "generated-key"))
        allow(IdempotencyRecords::CreateService).to receive(:call).and_return(OpenStruct.new(success?: false))
      end

      it "raises an IdempotencyError" do
        expect do
          described_class.transaction do
            described_class.unique!(invoice, invoice.id)
          end
        end.to raise_error(IdempotencyError, "Failed to create idempotency record")
      end
    end

    context "when an exception occurs in the block" do
      before do
        allow(IdempotencyRecords::KeyService).to receive(:call!).and_return(OpenStruct.new(idempotency_key: "generated-key"))
        allow(IdempotencyRecords::CreateService).to receive(:call).and_return(OpenStruct.new(success?: true))
      end

      it "cleans up the transaction context" do
        begin
          described_class.transaction do
            described_class.unique!(invoice, invoice.id)
            raise "Test error"
          end
        rescue StandardError
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
        resource = "test-resource"

        # Mock necessary services for transaction to succeed
        allow(IdempotencyRecords::KeyService).to receive(:call!).and_return(OpenStruct.new(idempotency_key: "key"))
        allow(IdempotencyRecords::CreateService).to receive(:call).and_return(OpenStruct.new(success?: true))

        described_class.transaction do
          described_class.unique!(resource, "value1", "value2")
          values_added = described_class.current_transaction.idempotent_resources[resource].first
        end

        expect(values_added).to eq(["value1", "value2"])
      end

      it "appends multiple calls for the same resource" do
        resource = "test-resource"
        values_list = nil

        # Mock necessary services for transaction to succeed
        allow(IdempotencyRecords::KeyService).to receive(:call!).and_return(OpenStruct.new(idempotency_key: "key"))
        allow(IdempotencyRecords::CreateService).to receive(:call).and_return(OpenStruct.new(success?: true))

        described_class.transaction do
          described_class.unique!(resource, "value1")
          described_class.unique!(resource, "value2", "value3")
          values_list = described_class.current_transaction.idempotent_resources[resource]
        end

        expect(values_list).to eq([["value1"], ["value2", "value3"]])
      end
    end
  end

  describe "Transaction" do
    let(:transaction) { described_class::Transaction.new }
    let(:invoice) { double('invoice') }

    describe "#ensure_idempotent!" do
      it "calls the key service and create service for each resource and values set" do
        resource1 = "resource1"
        resource2 = "resource2"
        values1 = [["a", "b"], ["c"]]
        values2 = [["d"]]

        transaction.idempotent_resources[resource1] = values1
        transaction.idempotent_resources[resource2] = values2

        expect(IdempotencyRecords::KeyService).to receive(:call!).with("a", "b").and_return(OpenStruct.new(idempotency_key: "key1"))
        expect(IdempotencyRecords::KeyService).to receive(:call!).with("c").and_return(OpenStruct.new(idempotency_key: "key2"))
        expect(IdempotencyRecords::KeyService).to receive(:call!).with("d").and_return(OpenStruct.new(idempotency_key: "key3"))

        expect(IdempotencyRecords::CreateService).to receive(:call).with(
          idempotency_key: "key1",
          resource: resource1
        ).and_return(OpenStruct.new(success?: true))

        expect(IdempotencyRecords::CreateService).to receive(:call).with(
          idempotency_key: "key2",
          resource: resource1
        ).and_return(OpenStruct.new(success?: true))

        expect(IdempotencyRecords::CreateService).to receive(:call).with(
          idempotency_key: "key3",
          resource: resource2
        ).and_return(OpenStruct.new(success?: true))

        transaction.ensure_idempotent!
      end

      it "raises IdempotencyError if create service fails" do
        transaction.idempotent_resources["resource"] = [["value"]]

        allow(IdempotencyRecords::KeyService).to receive(:call!).and_return(OpenStruct.new(idempotency_key: "key"))
        allow(IdempotencyRecords::CreateService).to receive(:call).and_return(OpenStruct.new(success?: false))

        expect { transaction.ensure_idempotent! }.to raise_error(IdempotencyError, "Failed to create idempotency record")
      end
    end

    describe "#valid?" do
      it "returns true when resources are present" do
        transaction.idempotent_resources["resource"] = [["value"]]
        expect(transaction.valid?).to be true
      end

      it "returns false when resources are empty" do
        expect(transaction.valid?).to be false
      end
    end
  end
end