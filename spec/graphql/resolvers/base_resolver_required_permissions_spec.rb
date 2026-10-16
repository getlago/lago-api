# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::BaseResolver do
  it "requires a permission on every organization-scoped resolver" do
    # Organization-scoped resolvers readable by every member, on purpose.
    allowed_without_permission = [
      # Current organization, used by every page. Sensitive fields are gated at field level.
      "Resolvers::OrganizationResolver",
      # Tax pickers on plans, add-ons, customers and invoices need the rates for roles
      # without organization:taxes:view. Tax changes require organization:taxes:update.
      "Resolvers::TaxesResolver",
      "Resolvers::TaxResolver"
    ]

    Rails.autoloaders.main.eager_load_namespace(Resolvers)

    # Only app resolvers: specs define throwaway resolvers of their own.
    resolvers = described_class.descendants.select { |resolver| resolver.name&.start_with?("Resolvers::") }
    # Abstract base classes leave REQUIRED_PERMISSION to their subclasses.
    concrete = resolvers.reject { |resolver| resolvers.any? { |other| other.superclass == resolver } }

    missing = concrete
      .select { |resolver| resolver.include?(RequiredOrganization) }
      .reject { |resolver| resolver.const_defined?(:REQUIRED_PERMISSION) }
      .map(&:name)
      .sort

    expect(missing).to match_array(allowed_without_permission),
      "Resolvers without REQUIRED_PERMISSION: #{(missing - allowed_without_permission).join(", ")}"
  end
end
