# frozen_string_literal: true

require "rails_helper"

module PermissionsTypeSpec
  class QueryType < Types::BaseObject
    field :permissions, Types::PermissionsType, null: false

    def permissions
      {
        "products_view" => true,
        "products_create" => false,
        "products_update" => true,
        "products_delete" => false
      }
    end
  end

  class TestSchema < GraphQL::Schema
    query(QueryType)
  end
end

RSpec.describe Types::PermissionsType do
  it "matches the list of default permissions" do
    all_boolean = described_class.fields.values.all? do |f|
      f.type.to_type_signature == "Boolean!"
    end
    expect(all_boolean).to be_truthy

    deprecated_aliases = %w[
      product_categories_view product_categories_create product_categories_update product_categories_delete
      product_filters_view product_filters_create product_filters_update product_filters_delete
    ]
    gql_field_names = described_class.fields.keys.map(&:underscore)
    rails_field_names = Permission.permissions_hash.keys.map { |k| k.tr(":", "_") }
    expect(gql_field_names - deprecated_aliases).to match_array(rails_field_names)
    expect(deprecated_aliases).to all(satisfy { |name| described_class.fields[name.camelize(:lower)].deprecation_reason.present? })
  end

  it "resolves deprecated category and filter permissions from product permissions" do
    result = PermissionsTypeSpec::TestSchema.execute(<<~GQL)
      query {
        permissions {
          productsView
          productsCreate
          productsUpdate
          productsDelete
          productCategoriesView
          productCategoriesCreate
          productCategoriesUpdate
          productCategoriesDelete
          productFiltersView
          productFiltersCreate
          productFiltersUpdate
          productFiltersDelete
        }
      }
    GQL

    expect(result["data"]["permissions"]).to eq(
      "productsView" => true,
      "productsCreate" => false,
      "productsUpdate" => true,
      "productsDelete" => false,
      "productCategoriesView" => true,
      "productCategoriesCreate" => false,
      "productCategoriesUpdate" => true,
      "productCategoriesDelete" => false,
      "productFiltersView" => true,
      "productFiltersCreate" => false,
      "productFiltersUpdate" => true,
      "productFiltersDelete" => false
    )
  end
end
