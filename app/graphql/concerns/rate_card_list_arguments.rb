# frozen_string_literal: true

# The filters of the plan and contract rate card pages, shared by both
# resolvers so the two lists filter the same way.
module RateCardListArguments
  extend ActiveSupport::Concern

  included do
    argument :has_rate_overrides, GraphQL::Types::Boolean, required: false
    argument :product_category_ids, [GraphQL::Types::ID], required: false
    argument :product_filter_ids, [GraphQL::Types::ID], required: false
    argument :product_ids, [GraphQL::Types::ID], required: false
    argument :product_type, Types::Products::ProductTypeEnum, required: false
    argument :search_term, GraphQL::Types::String, required: false
    argument :without_product_category, GraphQL::Types::Boolean, required: false
    argument :without_product_filter, GraphQL::Types::Boolean, required: false
  end
end
