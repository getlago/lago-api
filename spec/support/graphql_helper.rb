# frozen_string_literal: true

module GraphQLHelper
  def controller
    @controller ||= GraphqlController.new.tap do |ctrl|
      ctrl.set_request! ActionDispatch::Request.new({})
    end
  end

  def execute_graphql(query, **kwargs)
    args = kwargs.merge(
      context: { controller: controller }
    )

    LagoApiSchema.execute(
      query,
      **args
    )
  end
end
