# frozen_string_literal: true

class GraphqlChannel < ApplicationCable::Channel
  def subscribed
  end

  def execute(data)
    # Not expired_jwt_token: that would log out an active user. The client reconnects with its renewed token.
    if connection.token_expired?
      connection.close(reason: "token_expired", reconnect: true)
      return
    end

    return transmit_error(code: connection.auth_error_code, status: 401) if connection.auth_error_code
    return transmit_error(code: "unauthorized", status: 401) unless current_user

    if data["query"].to_s.length > GraphqlController::MAX_QUERY_LENGTH
      return transmit_error(code: "query_is_too_large", status: 413)
    end

    variables = begin
      ensure_hash(data["variables"])
    rescue JSON::ParserError, ArgumentError
      return transmit_error(code: "invalid_variables", status: 422)
    end

    # Looked up for each operation, so a membership revoked since the last one is not reused.
    organization_membership = find_organization_membership
    membership = organization_membership if session_allowed_in?(organization_membership&.organization)

    query = GraphQL::Query.new(
      LagoApiSchema,
      data["query"],
      variables:,
      operation_name: data["operationName"],
      context: {
        channel: self,
        login_method: connection.session_claims[:login_method],
        session_claims: connection.session_claims,
        current_user:,
        current_organization: membership&.organization,
        current_membership: membership,
        organization_refused_for_session: organization_membership.present? && membership.nil?,
        permissions: membership&.permissions_hash || {}
      }
    )

    # A query that does not parse has no selected operation, and query.result returns its errors.
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

  # When each subscription of this channel last passed its access check during a stream.
  def access_checked_at
    @access_checked_at ||= {}
  end

  def unsubscribed
    Array(@subscription_ids).each { |id| LagoApiSchema.subscriptions.delete_subscription(id) }
  end

  private

  def transmit_error(code:, status:)
    transmit({result: {errors: [{message: code, extensions: {status:, code:}}]}, more: false})
  end

  # Channel params are logged by ActionCable: they carry the organization id, never a credential.
  def current_user
    connection.current_user
  end

  def find_organization_membership
    organization_id = params["organization_id"]
    return if current_user.nil? || organization_id.blank?

    current_user.memberships.active.find_by(organization_id:)
  end

  # Same rule as AuthenticableUser: the session must be allowed to open the organization.
  def session_allowed_in?(organization)
    organization.present? && organization.accessible_by_session?(**connection.session_claims)
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
