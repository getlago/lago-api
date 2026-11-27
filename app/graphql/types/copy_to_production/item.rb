# frozen_string_literal: true

module Types
  module CopyToProduction
    class Item < Types::BaseObject
      graphql_name "CopyToProductionItem"
      description "A production item created by Copy to production"

      field :code, String, null: true
      field :id, ID, null: false
      field :item_type, Types::CopyToProduction::ItemTypeEnum, null: false
      field :name, String, null: true

      def id
        object.record.id
      end

      def code
        object.record.code
      end

      def name
        object.record.name
      end
    end
  end
end
