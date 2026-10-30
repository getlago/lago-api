# frozen_string_literal: true

class LagoApiSchema < GraphQL::Schema
  # The ActionCable transport delivers a subscription's final update (unsubscribe with a value) but keeps the
  # subscription registered. It is removed here once delivered, as GraphQL::Subscriptions#execute does.
  class ActionCableSubscriptions < GraphQL::Subscriptions::ActionCableSubscriptions
    def deliver(subscription_id, result)
      super
      delete_subscription(subscription_id) if result.context.namespace(:subscriptions)[:final_update]
    end
  end

  mutation(Types::MutationType)
  query(Types::QueryType)
  subscription(Types::GraphqlSubscriptionType)

  use ActionCableSubscriptions

  # For batch-loading (see https://graphql-ruby.org/dataloader/overview.html)
  use GraphQL::Dataloader

  max_depth 15
  max_complexity 350

  # A number too large for its column (bigint amounts, integer terms) fails when it is saved.
  rescue_from(ActiveModel::RangeError, ActiveRecord::RangeError) do
    raise GraphQL::ExecutionError.new(
      "Unprocessable Entity",
      extensions: {status: 422, code: "unprocessable_entity", details: {"base" => ["value_is_out_of_range"]}}
    )
  end

  # The schema is only described to clients (__schema, __type) in development and test, where
  # the front codegen and the schema dump specs need it. Elsewhere it stays hidden unless
  # LAGO_GRAPHQL_INTROSPECTION_ENABLED is set, for example on an API booted only to run codegen.
  def self.introspection_enabled?(env: Rails.env, flag: ENV["LAGO_GRAPHQL_INTROSPECTION_ENABLED"])
    env.development? || env.test? || ActiveModel::Type::Boolean.new.cast(flag) == true
  end

  unless introspection_enabled?
    disable_introspection_entry_points
    # Field name suggestions ("Did you mean ...?") would let a client rebuild the schema anyway.
    did_you_mean nil
  end

  # GraphQL-Ruby calls this when something goes wrong while running a query:

  # Union and Interface Resolution
  def self.resolve_type(_abstract_type, _obj, _ctx)
    # TODO: Implement this method
    # to return the correct GraphQL object type for `obj`
    raise(GraphQL::RequiredImplementationMissingError)
  end

  # Relay-style Object Identification:

  # Return a string UUID for `object`
  def self.id_from_object(object, type_definition, _query_ctx)
    # For example, use Rails' GlobalID library (https://github.com/rails/globalid):
    object_id = object.to_global_id.to_s
    # Remove this redundant prefix to make IDs shorter:
    object_id = object_id.sub("gid://#{GlobalID.app}/", "")
    encoded_id = Base64.urlsafe_encode64(object_id)
    # Remove the "=" padding
    encoded_id = encoded_id.sub(/=+/, "")
    # Add a type hint
    type_hint = type_definition.graphql_name.first
    "#{type_hint}_#{encoded_id}"
  end

  # Given a string UUID, find the object
  def self.object_from_id(encoded_id_with_hint, _query_ctx)
    # For example, use Rails' GlobalID library (https://github.com/rails/globalid):
    # Split off the type hint
    _type_hint, encoded_id = encoded_id_with_hint.split("_", 2)
    # Decode the ID
    id = Base64.urlsafe_decode64(encoded_id)
    # Rebuild it for Rails then find the object:
    full_global_id = "gid://#{GlobalID.app}/#{id}"
    GlobalID::Locator.locate(full_global_id)
  end

  default_max_page_size 25
end
