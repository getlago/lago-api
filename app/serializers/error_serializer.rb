# frozen_string_literal: true

class ErrorSerializer < ModelSerializer
  def serialize
    {
      status: 422,
      error: 'Unprocessable entity',
      message: model.error,
      input_params: model.input_params
    }
  end
end
