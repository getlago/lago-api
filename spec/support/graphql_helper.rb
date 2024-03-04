# frozen_string_literal: true

module GraphQLHelper
  def controller
    @controller ||= GraphqlController.new.tap do |ctrl|
      ctrl.set_request! ActionDispatch::Request.new({})
    end
  end

  # rubocop:disable Metrics/ParameterLists, Layout/LineLength
  def execute_graphql(current_user: nil, query: nil, current_organization: nil, customer_portal_user: nil, request: nil, **kwargs)
    # rubocop:enable Metrics/ParameterLists, Layout/LineLength
    args = kwargs.merge(
      context: {
        controller:,
        current_user:,
        current_organization:,
        customer_portal_user:,
        request:,
      },
    )

    LagoApiSchema.execute(
      query,
      **args,
    )
  end

  def expect_graphql_error(result:, message:)
    symbolized_result = result.to_h.deep_symbolize_keys

    expect(symbolized_result[:errors]).not_to be_empty

    error = symbolized_result[:errors].find do |e|
      e[:message].to_s == message.to_s || e[:extensions][:code].to_s == message.to_s
    end

    expect(error).to be_present, "error message for #{message} is not present"
  end

  def expect_unauthorized_error(result)
    expect_graphql_error(
      result:,
      message: :unauthorized,
    )
  end

  def expect_forbidden_error(result)
    expect_graphql_error(
      result:,
      message: :forbidden,
    )
  end

  def expect_unprocessable_entity(result)
    expect_graphql_error(
      result:,
      message: :unprocessable_entity,
    )
  end

  def expect_not_found(result)
    expect_graphql_error(
      result:,
      message: :not_found,
    )
  end
end
