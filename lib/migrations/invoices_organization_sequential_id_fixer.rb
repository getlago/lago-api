# frozen_string_literal: true

module Migrations
  class InvoicesOrganizationSequentialIdFixer
    def self.call
      new.call
    end

    def call
      # Ensure the last invoice for each organization with document numbering per_organization
      # has a correct organization_sequential_id. This is needed because we are using the
      # organization_sequential_id to generate the invoice number.
      #
      # If the last invoice organization_sequential_id does not match the non self-billed with
      # generated number invoices count, it means the organization has changed document numbering
      # from per_customer to per_organization before we released the fix that updates the last
      # invoice organization_sequential_id when the change happens.
      #
      # If the last invoice does not have a correct organization_sequential_id, we need to fix it.
      # We do this by setting the organization_sequential_id to count of non self-billed with generated
      # number invoice count.
      Organization.per_organization.find_each do |organization|
        last_organization_sequential_id = organization.invoices.maximum(:organization_sequential_id) || 0
        invoices_count = organization.invoices.non_self_billed.with_generated_number.count

        next if last_organization_sequential_id == invoices_count

        last_invoice = organization.invoices.non_self_billed.with_generated_number.order(created_at: :desc).limit(1)
        last_invoice.update_all(organization_sequential_id: invoices_count) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
