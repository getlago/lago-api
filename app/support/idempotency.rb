# frozen_string_literal: true

# Usage:
#
#   # Execute an operation idempotently
#   Idempotency.idempotent_transaction do
#     Idempotency.add(invoice.date)
#     Idempotency.add(invoice.customer_id)
#
#     # Perform your business logic here
#     result = perform_operation
#
#     # The idempotency_record is automatically created at the end of the transaction
#     Idempotency.resource = result
#   end
class Idempotency
  # Thread-local storage for the current transaction
  thread_mattr_accessor :current_transaction

  # Represents a transaction context for an idempotent operation
  class Transaction
    attr_accessor :components, :resource

    def initialize
      @components = []
      @resource = nil
    end

    # Generates a unique idempotency key from the collected components
    def idempotency_key
      Digest::SHA256.hexdigest(components.map(&:to_s).join("|"))
    end

    # Validates that at least one component has been added
    def valid?
      components.present?
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
  def self.idempotent_transaction
    # Create a new transaction context
    self.current_transaction = Transaction.new

    raise ArgumentError, "An idempotent_transaction cannot be created if we're already in a transaction" if ApplicationRecord.connection.open_transactions > 0

    # Ensure the transaction context is cleaned up even if an exception occurs
    ApplicationRecord.transaction do
      # Execute the block first to collect components
      original_return = yield

      # Validate that at least one component was added
      unless current_transaction.valid?
        raise ArgumentError, "At least one component must be added with Idempotency.add"
      end

      # Get the idempotency key based on components
      idempotency_key = current_transaction.idempotency_key

      # Try to create the idempotency record
      result = IdempotencyRecords::CreateService.call(
        idempotency_key:,
        resource: current_transaction.resource
      )

      # we're not idempotent, rollback
      raise ActiveRecord::Rollback unless result.success?

      original_return
    ensure
      # Clean up the transaction context
      self.current_transaction = nil
    end
  end

  # Adds a component to the idempotency key generation.
  # This method can only be called within an idempotent_transaction block.
  #
  # @param component [Object] A value that contributes to the idempotency key
  # @raise [ArgumentError] If called outside of an idempotent_transaction block
  def self.add(component)
    raise ArgumentError, "Idempotency.add can only be called within an idempotent_transaction block" unless current_transaction

    current_transaction.components << component
    nil
  end

  # Sets the resource for the current transaction.
  # This method can only be called within an idempotent_transaction block.
  #
  # @param resource [Object] The resource to associate with this idempotent operation
  # @raise [ArgumentError] If called outside of an idempotent_transaction block
  def self.resource=(resource)
    raise ArgumentError, "Idempotency.resource= can only be called within an idempotent_transaction block" unless current_transaction

    current_transaction.resource = resource
  end
end
