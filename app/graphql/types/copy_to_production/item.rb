# frozen_string_literal: true

module Types
  module CopyToProduction
    class Item < Types::BaseObject
      graphql_name "CopyToProductionItem"
      description "An item of Copy to production, in the sandbox when it is to be copied, in production otherwise"

      field :code, String, null: true
      field :id, ID, null: false
      field :item_type, Types::CopyToProduction::ItemTypeEnum, null: false
      field :name, String, null: true

      def id
        object.record.id
      end

      def code
        object.record.try(:code)
      end

      def name
        object.record.try(:name)
      end
    end
  end
end
