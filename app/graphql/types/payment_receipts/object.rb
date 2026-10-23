# frozen_string_literal: true

module Types
  module PaymentReceipts
    class Object < Types::BaseObject
      description "PaymentReceipt"
      graphql_name "PaymentReceipt"

      field :id, ID, null: false

      field :file_url, String, null: true
      field :file_url_expires_at, GraphQL::Types::ISO8601DateTime, null: true
      field :number, String, null: false
      field :organization, Types::Organizations::OrganizationType, null: false
      field :payment, Types::Payments::Object, null: false
      field :xml_url, String, null: true
      field :xml_url_expires_at, GraphQL::Types::ISO8601DateTime, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false

      # NOTE: Document urls read the organization expiry window
      dataload_association_for :organization, :file_url, :file_url_expires_at, :xml_url, :xml_url_expires_at
    end
  end
end
