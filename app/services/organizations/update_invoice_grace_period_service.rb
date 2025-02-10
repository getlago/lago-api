# frozen_string_literal: true

module Organizations
  class UpdateInvoiceGracePeriodService < BaseService
    def initialize(organization:, grace_period:)
      @organization = organization
      @grace_period = grace_period.to_i
      super
    end

    def call
      old_grace_period = organization.invoice_grace_period.to_i

      if grace_period != old_grace_period
        organization.invoice_grace_period = grace_period
        organization.save!

        Invoices::UpdateAllInvoiceGracePeriodFromOrganizationJob.perform_later(organization, old_grace_period)
      end

      result.organization = organization
      result
    end

    private

    attr_reader :organization, :grace_period
  end
end
