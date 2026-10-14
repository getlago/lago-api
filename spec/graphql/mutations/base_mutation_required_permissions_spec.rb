# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::BaseMutation do
  it "requires a permission on every organization-scoped mutation" do
    Rails.autoloaders.main.eager_load_namespace(Mutations)

    # Only app mutations: specs define throwaway mutations of their own.
    mutations = described_class.descendants.select { |mutation| mutation.name&.start_with?("Mutations::") }
    # Abstract base classes (e.g. payment provider bases) leave REQUIRED_PERMISSION to their subclasses.
    concrete = mutations.reject { |mutation| mutations.any? { |other| other.superclass == mutation } }

    missing = concrete
      .select { |mutation| mutation.include?(RequiredOrganization) }
      .reject { |mutation| mutation.const_defined?(:REQUIRED_PERMISSION) }
      .map(&:name)
      .sort

    expect(missing).to be_empty, "Mutations without REQUIRED_PERMISSION: #{missing.join(", ")}"
  end
end
