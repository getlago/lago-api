# frozen_string_literal: true

module GraphQLHelper
  def controller
    @controller ||= GraphqlController.new.tap do |ctrl|
      ctrl.set_request! ActionDispatch::Request.new({})
    end
  end

  def execute_graphql(current_user: nil, query: nil, **kwargs)
    return unless query 

    args = kwargs.merge(
      context: { controller: controller, current_user: current_user }
    )

    LagoApiSchema.execute(
      query,
      **args
    )
  end

  def expect_graphql_error(result:, message:)
    symbolized_result = result.to_h.deep_symbolize_keys

    expect(symbolized_result[:errors]).not_to be_empty

    error = symbolized_result[:errors].find { |e| e[:message].to_s == message.to_s }

    expect(error).to be_present, "error message for #{message} is not present"
  end

  def expect_unauthorized_error(result)
    expect_graphql_error(
      result: result,
      message: :unauthorized
    )
  end
end
