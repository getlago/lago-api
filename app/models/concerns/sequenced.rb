# frozen_string_literal: true

module Sequenced
  extend ActiveSupport::Concern

  included do
    scope :with_sequential_id, -> { where.not(sequential_id: nil) }
    scope :with_org_sequential_id, -> { where.not(organization_sequential_id: nil) }

    before_save :ensure_sequential_id
    before_save :ensure_organization_sequential_id, if: -> { self.class.to_s == 'Invoice' }

    private

    def ensure_sequential_id
      return if sequential_id.present?

      self.sequential_id = generate_sequential_id
    end

    def ensure_organization_sequential_id
      return if organization_sequential_id.present? && organization_sequential_id > 0

      self.organization_sequential_id = generate_organization_sequential_id
    end

    def generate_sequential_id
      result = self.class.with_advisory_lock(
        "#{self.class.name.underscore}_lock",
        transaction: true,
        timeout_seconds: 10.seconds,
      ) do
        sequential_id = sequence_scope.with_sequential_id.order(sequential_id: :desc).limit(1).pick(:sequential_id)
        sequential_id ||= 0

        loop do
          sequential_id += 1

          break sequential_id unless sequence_scope.exists?(sequential_id:)
        end
      end

      # NOTE: If the application was unable to acquire the lock, the block returns false
      raise(SequenceError, 'Unable to acquire lock on the database') unless result

      result
    end

    def generate_organization_sequential_id
      result = Invoice.with_advisory_lock(
        'invoice_lock',
        transaction: true,
        timeout_seconds: 10.seconds,
      ) do
        org_sequential_id = organization_sequence_scope
          .with_org_sequential_id
          .order(organization_sequential_id: :desc)
          .limit(1)
          .pick(:organization_sequential_id)
        org_sequential_id ||= 0

        loop do
          org_sequential_id += 1

          break org_sequential_id unless organization_sequence_scope.exists?(organization_sequential_id:)
        end
      end

      # NOTE: If the application was unable to acquire the lock, the block returns false
      raise(SequenceError, 'Unable to acquire lock on the database') unless result

      result
    end

    def sequence_scope
      self.class.class_exec(self, &self.class.sequenced_options[:scope])
    end

    def organization_sequence_scope
      self.class.class_exec(self, &self.class.sequenced_options[:organization_scope])
    end
  end

  class_methods do
    def sequenced(scope:, organization_scope: nil)
      self.sequenced_options = { scope:, organization_scope: }
    end

    def sequenced_options=(options)
      @sequenced_options = options
    end

    def sequenced_options
      @sequenced_options
    end
  end

  class SequenceError < StandardError; end
end
