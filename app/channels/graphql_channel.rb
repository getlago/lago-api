# frozen_string_literal: true

class GraphqlChannel < ApplicationCable::Channel
  def subscribed
    stream_from params[:channel]
  end

  def unsubscribed; end

  def execute(data)
    LagoApiSchema.execute(
      query: data["query"],
      variables: data["variables"],
      operation_name: data["operationName"],
      context: {
        current_user: current_user,
        channel: self
      }
    )
  end
end