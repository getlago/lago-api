# frozen_string_literal: true

# Usage:
#
#   # Execute an operation idempotently
#   Idempotency.transaction do
#     Idempotency.unique!(invoice, invoice.date, invoice.customer_id)

#     # Perform your business logic here
#     result = perform_operation
#   end
class Idempotency
  # Thread-local storage for the current transaction
  thread_mattr_accessor :current_transaction

  # Represents a transaction context for an idempotent operation
  class Transaction
    attr_accessor :idempotent_resources

    def initialize
      @idempotent_resources = Hash.new { |k, v| k[v] = [] }
    end

    def ensure_idempotent!
      idempotent_resources.each do |resource, values|
        # generate idempotency key for this resource
        idempotency_key = IdempotencyRecords::KeyService.call!(*values).idempotency_key

        # try and generate a resource
        result = IdempotencyRecords::CreateService.call(
          idempotency_key:,
          resource:
        )
        # raise in case the create service fails
        raise IdempotencyError.new("Failed to create idempotency record") unless result.success?
      end
    end

    # Validates that at least one component has been added
    def valid?
      !idempotent_resources.empty?
    end
  end

  # Executes a block within an idempotent transaction.
  # Any calls to Idempotency.add within the block will contribute
  # to the idempotency key generation.
  #
  # This method wraps the execution in a database transaction to ensure
  # atomicity of the operations performed within the block.
  #
  # @yield A block that contains idempotent operations
  # @return [Object] The result of the block or the existing resource if the operation is idempotent
  # @raise [Exception] If an error occurs during the block execution
  # @raise [ArgumentError] If no components are added to generate an idempotency key
  def self.transaction
    # Create a new transaction context
    self.current_transaction = Transaction.new

    raise ArgumentError, "An idempotent_transaction cannot be created when already in a transaction" if ApplicationRecord.connection.open_transactions > 0

    # Ensure the transaction context is cleaned up even if an exception occurs
    ApplicationRecord.transaction do
      # Execute the block first to collect components
      original_return = yield

      # Validate that at least one component was added
      unless current_transaction.valid?
        raise ArgumentError, "At least one component must be added with Idempotency.add"
      end

      current_transaction.ensure_idempotent!

      original_return
    ensure
      # Clean up the transaction context
      self.current_transaction = nil
    end
  end

  # Adds a resource to the idempotency key generation.
  # This method can only be called within an Idempotency.transaction block.
  #
  # @param resource [Object] Which resource we're guaranteeing uniqueness for
  # @raise [ArgumentError] If called outside of a transaction block
  def self.unique!(resource, *values)
    raise ArgumentError, "Idempotency.unique! can only be called within an idempotent_transaction block" unless current_transaction

    current_transaction.idempotent_resources[resource] << values
    nil
  end
end
