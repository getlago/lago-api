# frozen_string_literal: true

class GraphqlChannel < ApplicationCable::Channel
  def subscribed
  end

  def execute(data)
    if connection.auth_error_code
      code = connection.auth_error_code
      transmit({result: {errors: [{message: code, extensions: {status: 401, code:}}]}, more: false})
      return
    end

    query = GraphQL::Query.new(
      LagoApiSchema,
      data["query"],
      variables: ensure_hash(data["variables"]),
      operation_name: data["operationName"],
      context: {
        channel: self,
        current_user:,
        current_organization:,
        current_membership:,
        permissions: current_membership&.permissions_hash || {}
      }
    )

    # Queries and mutations go through GraphqlController, the socket only serves subscriptions.
    # A query that does not parse has no selected operation and gets its errors from query.result.
    if query.selected_operation && !query.subscription?
      transmit({result: {errors: [{message: "Only subscriptions are supported on this channel"}]}, more: false})
      return
    end

    result = query.result
    payload = {result: result.to_h}

    # Track the subscription here so we can remove it on unsubscribe.
    if result.context[:subscription_id]
      @subscription_ids ||= []
      @subscription_ids << result.context[:subscription_id]
    end

    if result.context[:subscription_id]
      transmit(payload.merge(more: true))
    else
      transmit(payload.merge(more: false))
    end
  end

  def unsubscribed
    Array(@subscription_ids).each { |id| LagoApiSchema.subscriptions.delete_subscription(id) }
  end

  private

  # The user comes from the token authenticated by the connection. The organization id is a
  # channel param (graphql-ruby-client ActionCableLink `connectionParams`), mirroring the
  # x-lago-organization header of the HTTP endpoint. Channel params end up in the logs,
  # so they must never carry a credential.
  def current_user
    connection.current_user
  end

  def current_membership
    return @current_membership if defined?(@current_membership)

    organization_id = params["organization_id"]
    @current_membership = if current_user && organization_id.present?
      current_user.memberships.active.find_by(organization_id:)
    end
  end

  def current_organization
    current_membership&.organization
  end

  def ensure_hash(ambiguous_param)
    case ambiguous_param
    when String
      if ambiguous_param.present?
        ensure_hash(JSON.parse(ambiguous_param))
      else
        {}
      end
    when Hash, ActionController::Parameters
      ambiguous_param
    when nil
      {}
    else
      raise ArgumentError, "Unexpected parameter: #{ambiguous_param}"
    end
  end
end
