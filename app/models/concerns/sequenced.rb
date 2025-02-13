# frozen_string_literal: true

module Sequenced
  extend ActiveSupport::Concern

  included do
    scope :with_sequential_id, -> { where.not(sequential_id: nil) }

    before_save :ensure_sequential_id

    private

    def ensure_sequential_id
      return if sequential_id.present?
      return unless should_assign_sequential_id?

      self.sequential_id = generate_sequential_id
    end

    def should_assign_sequential_id?
      true
    end

    def generate_sequential_id
      result = self.class.with_advisory_lock(
        lock_key_value,
        transaction: true,
        timeout_seconds: 10.seconds
      ) do
        sequential_id = sequence_scope.with_sequential_id.order(sequential_id: :desc).limit(1).pick(:sequential_id)
        sequential_id ||= 0

        loop do
          sequential_id += 1

          break sequential_id unless sequence_scope.exists?(sequential_id:)
        end
      end

      # NOTE: If the application was unable to acquire the lock, the block returns false
      raise(SequenceError, "Unable to acquire lock on the database") unless result

      result
    end

    def sequence_scope
      self.class.class_exec(self, &self.class.sequenced_options[:scope])
    end

    def lock_key_value
      "#{self.class.class_exec(self, &self.class.sequenced_lock_key) || self.class.name.underscore}_lock"
    end
  end

  class_methods do
    def sequenced(scope:, lock_key: nil)
      self.sequenced_options = {scope:}
      self.sequenced_lock_key = lock_key
    end

    # rubocop:disable ThreadSafety/InstanceVariableInClassMethod
    def sequenced_options=(options)
      @sequenced_options = options
    end

    def sequenced_options
      @sequenced_options
    end

    def sequenced_lock_key=(lock_key)
      @sequenced_lock_key = lock_key
    end

    def sequenced_lock_key
      @sequenced_lock_key
    end
    # rubocop:enable ThreadSafety/InstanceVariableInClassMethod
  end

  class SequenceError < StandardError; end
end
