# frozen_string_literal: true

module Invoices
  class UpdateAllInvoiceGracePeriodFromOrganizationService < BaseService
    def initialize(organization:, old_grace_period:)
      @organization = organization
      @old_grace_period = old_grace_period

      super
    end

    def call
      organization.invoices.draft.find_each do |invoice|
        Invoices::UpdateGracePeriodFromOrganizationJob.perform_later(invoice:, old_grace_period:)
      end

      result
    end

    private

    attr_reader :organization, :old_grace_period
  end
end
