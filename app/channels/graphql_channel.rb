# frozen_string_literal: true

class GraphqlChannel < ApplicationCable::Channel
  def subscribed
  end

  def execute(data)
    query = data["query"]
    variables = ensure_hash(data["variables"])
    operation_name = data["operationName"]

    context = {
      channel: self, # important for GraphQL subscriptions
    }

    result = LagoApiSchema.execute(
      query: query,
      context: context,
      variables: variables,
      operation_name: operation_name
    )

    transmit(result.to_h)
  end

  private

  def ensure_hash(ambiguous_param)
    case ambiguous_param
    when String
      ambiguous_param.present? ? JSON.parse(ambiguous_param) : {}
    when Hash, ActionController::Parameters
      ambiguous_param
    when nil
      {}
    else
      raise ArgumentError, "Unexpected parameter: #{ambiguous_param}"
    end
  end
end
